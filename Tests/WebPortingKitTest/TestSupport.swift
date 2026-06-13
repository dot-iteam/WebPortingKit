import NIOCore
import NIOEmbedded
import NIOHTTP1
import Testing
@testable import WebPortingKit

actor BodyRecorder {
    private var receivedBody: String?
    private var routeCallCount = 0

    func record(_ body: String?) {
        receivedBody = body
        routeCallCount += 1
    }

    func body() -> String? {
        receivedBody
    }

    func calls() -> Int {
        routeCallCount
    }
}

enum RouteError: Error {
    case failed
}

func stringBody(from request: HTTPRequest) -> String? {
    request.body?.getString(
        at: request.body?.readerIndex ?? 0,
        length: request.body?.readableBytes ?? 0
    )
}

func makeHTTP1Handler(
    app: HTTPApplication<DefaultHTTPRoutingHandler>,
    maximumBodySize: Int = HTTPServer<DefaultHTTPRoutingHandler>.defaultMaximumBodySize
) -> HTTPServer<DefaultHTTPRoutingHandler>.HTTPHandler {
    HTTPServer<DefaultHTTPRoutingHandler>.HTTPHandler(
        version: .http1_1,
        app: app,
        maximumBodySize: maximumBodySize
    )
}

func makeRequestHead(
    method: HTTPMethod,
    uri: String,
    headers: HTTPHeaders = HTTPHeaders()
) -> HTTPRequestHead {
    HTTPRequestHead(
        version: .http1_1,
        method: method,
        uri: uri,
        headers: headers
    )
}

func waitForRecordedBody(
    _ recorder: BodyRecorder,
    channel: EmbeddedChannel,
    attempts: Int = 50
) async throws -> String? {
    for _ in 0..<attempts {
        channel.embeddedEventLoop.run()
        if let body = await recorder.body() {
            return body
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    return await recorder.body()
}

func waitForOutboundPart(
    channel: EmbeddedChannel,
    attempts: Int = 50
) async throws -> HTTPServerResponsePart? {
    for _ in 0..<attempts {
        channel.embeddedEventLoop.run()
        if let part = try channel.readOutbound(as: HTTPServerResponsePart.self) {
            return part
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    return try channel.readOutbound(as: HTTPServerResponsePart.self)
}

func requireResponseHead(
    from channel: EmbeddedChannel,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws -> HTTPResponseHead? {
    let responsePart = try await waitForOutboundPart(channel: channel)
    let responseHead = try #require(responsePart, sourceLocation: sourceLocation)
    guard case .head(let response) = responseHead else {
        Issue.record("Expected response head, got \(responseHead)", sourceLocation: sourceLocation)
        return nil
    }
    return response
}

func requireImmediateResponseHead(
    from channel: EmbeddedChannel,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> HTTPResponseHead? {
    let responsePart = try channel.readOutbound(as: HTTPServerResponsePart.self)
    let responseHead = try #require(responsePart, sourceLocation: sourceLocation)
    guard case .head(let response) = responseHead else {
        Issue.record("Expected response head, got \(responseHead)", sourceLocation: sourceLocation)
        return nil
    }
    return response
}

func assertNextOutboundPartIsResponseEnd(
    channel: EmbeddedChannel,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let responseEnd = try channel.readOutbound(as: HTTPServerResponsePart.self) as HTTPServerResponsePart?
    guard case .end = responseEnd else {
        Issue.record("Expected response end, got \(String(describing: responseEnd))", sourceLocation: sourceLocation)
        return
    }
}

func readUntilResponseEnd(
    channel: EmbeddedChannel,
    attempts: Int = 50,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    for _ in 0..<attempts {
        channel.embeddedEventLoop.run()
        while let part = try channel.readOutbound(as: HTTPServerResponsePart.self) {
            if case .end = part {
                return
            }
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Expected response end", sourceLocation: sourceLocation)
}
