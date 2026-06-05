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
import NIOPosix
import NIOHPACK
#if canImport(NIOTransportServices)
import NIOTransportServices
#endif
public enum HTTPServerIdentity: Sendable {
    case secure(SecureIdentityPair)
    case http
}
public final class HTTPServer<RequestHandler: HTTPRequestHandler> {
    
    let group: EventLoopGroup
    #if canImport(NIOTransportServices)
    let bootstrap: NIOTSListenerBootstrap
    #else
    let bootstrap: ServerBootstrap
    #endif
    var channel: Channel?
    public var app: HTTPApplication<RequestHandler>
    public final class HTTPHandler : ChannelInboundHandler {
        public class RequestCombination: @unchecked Sendable {
            public var head: HTTPRequestHead?
            public var body: ByteBuffer?
            public init() {}
        }
        public final class ChannelCapture : @unchecked Sendable {
            public let version: HTTPVersion
            public var app: HTTPApplication<RequestHandler>
            public var context: ChannelHandlerContext
            public init(version: HTTPVersion, app: HTTPApplication<RequestHandler>, context: ChannelHandlerContext) {
                self.version = version
                self.app = app
                self.context = context
            }
        }
        public typealias InboundIn = HTTPServerRequestPart
        public typealias OutboundOut = HTTPServerResponsePart
        public let version: HTTPVersion
        public let app: HTTPApplication<RequestHandler>
        init(version: HTTPVersion, app: HTTPApplication<RequestHandler>) {
            self.version = version
            self.app = app
        }
        var combination: RequestCombination = .init()
        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let part = self.unwrapInboundIn(data)
            var trailers: HTTPHeaders? = nil
            switch part {
            case .head(let head):
                self.combination.head = head
                return
            case .body(var buffer):
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
                let head = HTTPServerResponsePart.head(.init(version: version, status: .badRequest, headers: HTTPHeaders([])))
                context.channel.write(head, promise: nil)
                context.channel.write(HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(bytes: []))), promise: nil)
                context.channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                return
            }
            let capture = ChannelCapture(version: version, app: app, context: context)
            let future = context.eventLoop.makeFutureWithTask { [combination, trailers, capture] in
                var httpContext = HTTPContext(request: .init(url: URL(string: head.uri) ?? URL(string: "/")!, method: head.method, headers: head.headers, body: combination.body, trailers: trailers, cookies: getRequestCookies(headers: head.headers)))
                do {
                    try await capture.app.handler.route(context: &httpContext)
                    return Result<HTTPContext, Error>.success( httpContext)
                } catch {
                    return Result<HTTPContext, Error>.failure(error)
                }
            }
            future.whenComplete { [capture] result in
                let context = capture.context
                switch result {
                case .success(let someHttpContext):
                    guard case .success(let httpContext) = someHttpContext else {
                        if case .failure(let error) = result {
                            let describeError = error.localizedDescription
                            let head = HTTPServerResponsePart.head(.init(version: capture.version, status: .internalServerError, headers: HTTPHeaders([("content-length", "\(describeError.utf8.count)")])))
                            context.channel.write(head, promise: nil)
                            context.channel.write(HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: error.localizedDescription))), promise: nil)
                            context.channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                        }
                        return
                    }
                    var httpResponse = httpContext.response
                    if let responseBody = httpResponse.body {
                        httpResponse.headers.replaceOrAdd(name: "content-length", value: "\(responseBody.readableBytes)")
                    }
                    let responseHead = HTTPResponseHead(version: capture.version, status: httpResponse.status, headers: httpResponse.headers)
                    context.channel.write(HTTPServerResponsePart.head(responseHead), promise: nil)
                    if let responseBody = httpResponse.body {
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
                    let head = HTTPServerResponsePart.head(.init(version: capture.version, status: .internalServerError, headers: HTTPHeaders([])))
                    context.channel.write(head, promise: nil)
                    #endif
                    context.channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                }
                
            }

        }
    }
    public init(
        identity: HTTPServerIdentity = .http,
        app: HTTPApplication<RequestHandler>
    ) {
        self.app = app
        #if canImport(NIOTransportServices)
        group = NIOTSEventLoopGroup()
        var bootstrap = NIOTSListenerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(.init(SOL_SOCKET), .init(SO_REUSEADDR)), value: 1)
        #else
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(.init(SOL_SOCKET), .init(SO_REUSEADDR)), value: 1)
        #endif
            bootstrap = bootstrap.childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    var sslContext: NIOSSLContext?
                    var version: HTTPVersion
                    if case .secure(let security) = identity {
                        do {
                            sslContext = try makeSSLContext(from: security)
                        } catch {
                            fatalError(error.localizedDescription)
                        }
                        version = .http2
                    } else {
                        version = .http1_1
                    }
                    if let sslContext {
                        if version == .http2 {
                            try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: sslContext))
                        }
                        
                    }
                    if version == .http2 {
                        
                        _ = try channel.pipeline.syncOperations.configureHTTP2Pipeline(
                        mode: .server,
                        connectionConfiguration: NIOHTTP2Handler.ConnectionConfiguration(),
                        streamConfiguration: NIOHTTP2Handler.StreamConfiguration(),
                        inboundStreamInitializer: { [version] streamChannel in
                            streamChannel.pipeline.eventLoop.makeCompletedFuture {
                                try streamChannel.pipeline.syncOperations.addHandler(HTTP2FramePayloadToHTTP1ServerCodec())
                                try streamChannel.pipeline.syncOperations.addHandler(HTTPHandler(version: version, app: app))
                                try streamChannel.pipeline.syncOperations
                                    .addHandler(
                                        HTTPServerProtocolErrorHandler()
                                    )
                            }
                        })
                    } else {
                        try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                        try channel.pipeline.syncOperations.addHandler(HTTPHandler(version: version, app: app))
                    }
                }
            }.childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        self.bootstrap = bootstrap
    }
    public func start(host: String, port: Int) async {
        print("Binding HTTP Server to \(host):\(port)")
        channel = try? await bootstrap.bind(host: host, port: port).get()
        try? await channel?.closeFuture.get()
    }
    public func stop() async {
        try? await channel?.closeFuture.get()
    }
    deinit {
        try? group.syncShutdownGracefully()
    }
}

