//
//  Core.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-28.
//

import Foundation
import NIO
import NIOCore
import NIOHTTP1
import NIOHTTP2
import NIOSSL
import NIOTLS
import NIOPosix
import NIOHPACK
#if canImport(NIOTransportServices)
import NIOTransportServices
#endif
/// HTTPS application protocol mode for secure servers.
public enum HTTPSProtocolMode: Sendable {
    /// Serve HTTP/1.1 over TLS.
    case http1

    /// Serve HTTP/2 over TLS.
    case http2

    /// Negotiate HTTP/2 or HTTP/1.1 with ALPN.
    case negotiated
}

/// Network identity used by ``HTTPServer``.
public enum HTTPServerIdentity: Sendable {
    /// Serve HTTPS using the supplied key/certificate pair and protocol mode.
    case secure(SecureIdentityPair, mode: HTTPSProtocolMode = .http2)

    /// Serve plain HTTP/1.1 without TLS.
    case http
}
enum HTTPServerPipelineMode: Sendable {
    case http1
    case http2
    case negotiated
}
struct HTTPServerChannelConfiguration {
    let sslContext: NIOSSLContext?
    let pipelineMode: HTTPServerPipelineMode
}
func makeHTTPServerChannelConfiguration(identity: HTTPServerIdentity) throws -> HTTPServerChannelConfiguration {
    switch identity {
    case .http:
        return HTTPServerChannelConfiguration(sslContext: nil, pipelineMode: .http1)
    case .secure(let security, let mode):
        let sslContext = try makeSSLContext(from: security, mode: mode)
        switch mode {
        case .http1:
            return HTTPServerChannelConfiguration(sslContext: sslContext, pipelineMode: .http1)
        case .http2:
            return HTTPServerChannelConfiguration(sslContext: sslContext, pipelineMode: .http2)
        case .negotiated:
            return HTTPServerChannelConfiguration(sslContext: sslContext, pipelineMode: .negotiated)
        }
    }
}
/// Errors thrown while configuring or starting an HTTP server.
public enum HTTPServerError: Error, Sendable {
    /// The server could not create a valid bootstrap or event loop group.
    case invalidConfiguration
}

/// A SwiftNIO-backed HTTP server for a ``HTTPApplication``.
public final class HTTPServer<RoutingHandler: HTTPRoutingHandler>: @unchecked Sendable {
    /// Default maximum request body size, in bytes.
    public static var defaultMaximumBodySize: Int { 16 * 1024 * 1024 }
    var group: EventLoopGroup?
    #if canImport(NIOTransportServices)
    var bootstrap: NIOTSListenerBootstrap?
    #else
    var bootstrap: ServerBootstrap?
    #endif
    var channel: Channel?
    /// NIO channel handler that combines request frames and dispatches routes.
    public final class HTTPHandler : ChannelInboundHandler {
        /// Accumulates request head, body, trailers, and body-size state for one request.
        public class RequestCombination: @unchecked Sendable {
            /// The request head frame, if received.
            public var head: HTTPRequestHead?

            /// Accumulated request body bytes.
            public var body: ByteBuffer?

            /// Number of body bytes received so far.
            public var bodySize = 0

            /// Maximum allowed body size for this request.
            public var maximumBodySize = HTTPServer.defaultMaximumBodySize

            /// Whether the request body exceeded its limit.
            public var bodyTooLarge = false

            /// Creates an empty request accumulator.
            public init() {}
        }

        /// Captures channel state needed when an async route completes.
        public final class ChannelCapture : @unchecked Sendable {
            /// HTTP protocol version to use for the response head.
            public let version: HTTPVersion

            /// Application used to route the request.
            public var app: HTTPApplication<RoutingHandler>

            /// Channel context used to write the response.
            public var context: ChannelHandlerContext

            /// Creates a channel capture.
            public init(version: HTTPVersion, app: HTTPApplication<RoutingHandler>, context: ChannelHandlerContext) {
                self.version = version
                self.app = app
                self.context = context
            }
        }
        /// Inbound NIO message type handled by this channel handler.
        public typealias InboundIn = HTTPServerRequestPart

        /// Outbound NIO message type written by this channel handler.
        public typealias OutboundOut = HTTPServerResponsePart

        /// HTTP protocol version used for responses.
        public let version: HTTPVersion

        /// Application used to route completed requests.
        public let app: HTTPApplication<RoutingHandler>

        /// Server-wide maximum request body size.
        public let maximumBodySize: Int
        init(
            version: HTTPVersion,
            app: HTTPApplication<RoutingHandler>,
            maximumBodySize: Int = HTTPServer.defaultMaximumBodySize
        ) {
            self.version = version
            self.app = app
            self.maximumBodySize = maximumBodySize
        }
        var combination: RequestCombination = .init()
        private func effectiveMaximumBodySize(for head: HTTPRequestHead) -> Int {
            guard let provider = app.handler as? any HTTPBodyLimitProviding,
                  let routeMaximumBodySize = provider.maximumBodySize(for: head) else {
                return maximumBodySize
            }
            return min(maximumBodySize, routeMaximumBodySize)
        }
        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let part = self.unwrapInboundIn(data)
            var trailers: HTTPHeaders? = nil
            switch part {
            case .head(let head):
                self.combination.head = head
                self.combination.maximumBodySize = effectiveMaximumBodySize(for: head)
                if let contentLength = head.headers.first(name: "content-length"),
                   let bodySize = Int(contentLength),
                   bodySize > self.combination.maximumBodySize {
                    self.combination.bodyTooLarge = true
                }
                return
            case .body(var buffer):
                guard !self.combination.bodyTooLarge else {
                    return
                }
                self.combination.bodySize += buffer.readableBytes
                guard self.combination.bodySize <= self.combination.maximumBodySize else {
                    self.combination.body = nil
                    self.combination.bodyTooLarge = true
                    return
                }
                if self.combination.body == nil {
                    self.combination.body = context.channel.allocator.buffer(capacity: buffer.readableBytes)
                }
                self.combination.body?.writeBuffer(&buffer)
                return
            
            case .end(let receivedTrailers):
                trailers = receivedTrailers
                break
            }
            guard let head = combination.head else {
                self.combination = .init()
                let head = HTTPServerResponsePart.head(.init(version: version, status: .badRequest, headers: HTTPHeaders([])))
                context.channel.write(head, promise: nil)
                context.channel.write(HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(bytes: []))), promise: nil)
                context.channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                return
            }
            guard !combination.bodyTooLarge else {
                self.combination = .init()
                let responseHead = HTTPServerResponsePart.head(
                    .init(
                        version: version,
                        status: .payloadTooLarge,
                        headers: HTTPHeaders([("content-length", "0")])
                    )
                )
                context.channel.write(responseHead, promise: nil)
                context.channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                return
            }
            let body = combination.body
            self.combination = .init()
            let capture = ChannelCapture(version: version, app: app, context: context)
            let future = context.eventLoop.makeFutureWithTask { [head, body, trailers, capture] in
                var httpContext = HTTPContext(request: .init(url: URL(string: head.uri) ?? URL(fileURLWithPath: "/"), method: head.method, headers: head.headers, body: body, trailers: trailers, cookies: getRequestCookies(headers: head.headers)))
                let decision = try await capture.app.handler.routeWithDecision(context: &httpContext)
                return (httpContext, decision)
            }
            future.whenComplete { [capture] result in
                let context = capture.context
                switch result {
                case .success(let (httpContext, decision)):
                    guard decision == .respond else {
                        context.channel.close(promise: nil)
                        return
                    }
                    var httpResponse = httpContext.response
                    // A HEAD response must carry the same headers as the equivalent GET
                    // (including Content-Length) but must not include a message body.
                    let isHead = httpContext.request.method == .HEAD
                    if let responseBody = httpResponse.body {
                        httpResponse.headers.replaceOrAdd(name: "content-length", value: "\(responseBody.readableBytes)")
                    } else if HTTPServer<RoutingHandler>.allowsResponseBody(status: httpResponse.status) {
                        httpResponse.headers.replaceOrAdd(name: "content-length", value: "0")
                    }
                    let responseHead = HTTPResponseHead(version: capture.version, status: httpResponse.status, headers: httpResponse.headers)
                    context.channel.write(HTTPServerResponsePart.head(responseHead), promise: nil)
                    if let responseBody = httpResponse.body, !isHead {
                        _  = context.channel.write(HTTPServerResponsePart.body(.byteBuffer(responseBody)))
                    }
                    
                    context.channel
                        .writeAndFlush(
                            HTTPServerResponsePart.end(httpResponse.trailers),
                            promise: nil
                        )
                case .failure(let error):
                    let describeError = error.localizedDescription
                    #if DEBUG
                    let head = HTTPServerResponsePart.head(.init(version: capture.version, status: .internalServerError, headers: HTTPHeaders([("content-length", "\(describeError.utf8.count)"), ("content-type", "text/plain; charset=utf-8")])))
                    context.channel.write(head, promise: nil)
                    context.channel.write(HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: error.localizedDescription))), promise: nil)
                    #else
                    let head = HTTPServerResponsePart.head(.init(version: capture.version, status: .internalServerError, headers: HTTPHeaders([("content-length", "0")])))
                    context.channel.write(head, promise: nil)
                    #endif
                    context.channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                }
                
            }

        }
    }

    private static func allowsResponseBody(status: HTTPResponseStatus) -> Bool {
        !(status.code >= 100 && status.code < 200) && status != .noContent && status != .notModified
    }

    private static func configureHTTP1Pipeline(
        channel: Channel,
        app: HTTPApplication<RoutingHandler>,
        maximumBodySize: Int
    ) throws {
        try channel.pipeline.syncOperations.configureHTTPServerPipeline()
        try channel.pipeline.syncOperations.addHandler(
            HTTPHandler(version: .http1_1, app: app, maximumBodySize: maximumBodySize)
        )
    }

    private static func configureHTTP2Pipeline(
        channel: Channel,
        app: HTTPApplication<RoutingHandler>,
        maximumBodySize: Int
    ) throws {
        _ = try channel.pipeline.syncOperations.configureHTTP2Pipeline(
            mode: .server,
            connectionConfiguration: NIOHTTP2Handler.ConnectionConfiguration(),
            streamConfiguration: NIOHTTP2Handler.StreamConfiguration(),
            inboundStreamInitializer: { streamChannel in
                streamChannel.pipeline.eventLoop.makeCompletedFuture {
                    try streamChannel.pipeline.syncOperations.addHandler(HTTP2FramePayloadToHTTP1ServerCodec())
                    try streamChannel.pipeline.syncOperations.addHandler(
                        HTTPHandler(version: .http2, app: app, maximumBodySize: maximumBodySize)
                    )
                    try streamChannel.pipeline.syncOperations.addHandler(HTTPServerProtocolErrorHandler())
                }
            }
        )
    }

    private static func configureNegotiatedPipeline(
        channel: Channel,
        app: HTTPApplication<RoutingHandler>,
        maximumBodySize: Int
    ) throws {
        try channel.pipeline.syncOperations.addHandler(
            ApplicationProtocolNegotiationHandler { result, channel in
                switch result {
                case .negotiated("h2"):
                    return channel.eventLoop.makeCompletedFuture {
                        try configureHTTP2Pipeline(channel: channel, app: app, maximumBodySize: maximumBodySize)
                    }
                case .negotiated("http/1.1"), .fallback:
                    return channel.eventLoop.makeCompletedFuture {
                        try configureHTTP1Pipeline(channel: channel, app: app, maximumBodySize: maximumBodySize)
                    }
                case .negotiated:
                    return channel.close()
                }
            }
        )
    }
    private let identity: HTTPServerIdentity
    private let maximumBodySize: Int
    private let app: HTTPApplication<RoutingHandler>
    /// Creates an HTTP server for `app`.
    ///
    /// - Parameters:
    ///   - identity: Plain HTTP or HTTPS identity configuration.
    ///   - maximumBodySize: Server-wide maximum request body size in bytes.
    ///   - app: Application used to route requests.
    public init(
        identity: HTTPServerIdentity = .http,
        maximumBodySize: Int = HTTPServer.defaultMaximumBodySize,
        app: HTTPApplication<RoutingHandler>
    ) {
        self.identity = identity
        self.maximumBodySize = maximumBodySize
        self.app = app
    }
    private func boot() {
        #if canImport(NIOTransportServices)
        let group = NIOTSEventLoopGroup()
        self.group = group
        var bootstrap = NIOTSListenerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(.init(SOL_SOCKET), .init(SO_REUSEADDR)), value: 1)
        #else
        group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(.init(SOL_SOCKET), .init(SO_REUSEADDR)), value: 1)
        #endif
            bootstrap = bootstrap.childChannelInitializer { channel in
                channel.eventLoop
                    .makeCompletedFuture { [self] in
                    let configuration = try makeHTTPServerChannelConfiguration(identity: identity)
                    if let sslContext = configuration.sslContext {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: sslContext))
                    }
                    switch configuration.pipelineMode {
                    case .http1:
                        try Self.configureHTTP1Pipeline(
                            channel: channel,
                            app: app,
                            maximumBodySize: maximumBodySize
                        )
                    case .http2:
                        try Self.configureHTTP2Pipeline(
                            channel: channel,
                            app: app,
                            maximumBodySize: maximumBodySize
                        )
                    case .negotiated:
                        try Self.configureNegotiatedPipeline(
                            channel: channel,
                            app: app,
                            maximumBodySize: maximumBodySize
                        )
                    }
                }
            }.childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        self.bootstrap = bootstrap
    }
    private actor AtomicState: Sendable {
        var started: Bool = false
        var generation: Int = 0

        func markStarted() -> Int? {
            guard !started else {
                return nil
            }
            generation += 1
            started = true
            return generation
        }

        func currentGeneration() -> Int {
            generation
        }

        func finish(generation finishedGeneration: Int) {
            guard generation == finishedGeneration else {
                return
            }
            started = false
        }
    }
    private var state: AtomicState = .init()
    /// Binds the server and runs until the bound channel closes.
    ///
    /// Calling `start` while the same server instance is already started returns
    /// without rebinding. After ``stop()`` completes, the same instance can be started
    /// again.
    ///
    /// - Parameters:
    ///   - host: Hostname or IP address to bind.
    ///   - port: TCP port to bind.
    public func start(host: String, port: Int) async throws {
        guard let generation = await state.markStarted() else {
            return
        }
        boot()
        guard let bootstrap else {
            await finishRun(group: nil, generation: generation)
            throw HTTPServerError.invalidConfiguration
        }
        guard let group else {
            await finishRun(group: nil, generation: generation)
            throw HTTPServerError.invalidConfiguration
        }
        print("Binding HTTP Server to \(host):\(port)")
        do {
            let boundChannel = try await bootstrap.bind(host: host, port: port).get()
            channel = boundChannel
            try? await boundChannel.closeFuture.get()
            await finishRun(group: group, generation: generation)
        } catch {
            await finishRun(group: group, generation: generation)
            throw error
        }
    }

    /// Closes the bound server channel and shuts down its event loop group.
    ///
    /// Calling `stop` before the server is started, or after it has already stopped,
    /// is a no-op.
    public func stop() async {
        let generation = await state.currentGeneration()
        guard let channel else {
            return
        }
        let group = self.group
        try? await channel.close().get()
        try? await channel.closeFuture.get()
        await finishRun(group: group, generation: generation)
    }

    private func finishRun(group: EventLoopGroup?, generation: Int) async {
        if let group {
            try? await group.shutdownGracefully()
        }
        await state.finish(generation: generation)
        guard await state.currentGeneration() == generation else {
            return
        }
        channel = nil
        bootstrap = nil
        self.group = nil
    }
}

