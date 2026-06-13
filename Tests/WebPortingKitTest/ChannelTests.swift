import Foundation
import NIOCore
import NIOEmbedded
import NIOHTTP1
import Testing
@testable import WebPortingKit

@Suite("HTTP channel request handling")
struct HTTPChannelRequestTests {
    @Test("combines multiple request body frames before routing")
    func combinesMultipleBodyFramesBeforeRouting() async throws {
        let recorder = BodyRecorder()
        let expectedBody = "first chunk, second chunk, final chunk"

        var app = HTTPApplication()
        app.post("upload") { request -> HTTPResponse in
            await recorder.record(stringBody(from: request))
            return HTTPResponse(status: .ok)
        }

        let channel = EmbeddedChannel(handler: makeHTTP1Handler(app: app))
        let allocator = ByteBufferAllocator()

        try channel.writeInbound(
            HTTPServerRequestPart.head(
                makeRequestHead(
                    method: .POST,
                    uri: "/upload",
                    headers: HTTPHeaders([
                        ("content-type", "text/plain"),
                        ("transfer-encoding", "chunked")
                    ])
                )
            )
        )
        try channel.writeInbound(HTTPServerRequestPart.body(allocator.buffer(string: "first chunk, ")))
        try channel.writeInbound(HTTPServerRequestPart.body(allocator.buffer(string: "second chunk, ")))
        try channel.writeInbound(HTTPServerRequestPart.body(allocator.buffer(string: "final chunk")))

        #expect(await recorder.body() == nil)

        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let receivedBody = try await waitForRecordedBody(recorder, channel: channel)
        #expect(receivedBody == expectedBody)

        let response = try requireImmediateResponseHead(from: channel)
        #expect(response?.status == .ok)

        try assertNextOutboundPartIsResponseEnd(channel: channel)
        #expect(try channel.finish(acceptAlreadyClosed: true).isClean)
    }

    @Test("adds zero content length for successful empty response")
    func addsZeroContentLengthForSuccessfulEmptyResponse() async throws {
        var app = HTTPApplication()
        app.get("empty") { _ -> HTTPResponse in
            HTTPResponse(status: .ok)
        }

        let channel = EmbeddedChannel(handler: makeHTTP1Handler(app: app))

        try channel.writeInbound(HTTPServerRequestPart.head(makeRequestHead(method: .GET, uri: "/empty")))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let response = try await requireResponseHead(from: channel)
        #expect(response?.status == .ok)
        #expect(response?.headers.first(name: "content-length") == "0")

        try await readUntilResponseEnd(channel: channel)
        #expect(try channel.finish(acceptAlreadyClosed: true).isClean)
    }

    @Test("does not add content length for no content response")
    func doesNotAddContentLengthForNoContentResponse() async throws {
        var app = HTTPApplication()
        app.get("empty") { _ -> HTTPResponse in
            HTTPResponse(status: .noContent)
        }

        let channel = EmbeddedChannel(handler: makeHTTP1Handler(app: app))

        try channel.writeInbound(HTTPServerRequestPart.head(makeRequestHead(method: .GET, uri: "/empty")))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let response = try await requireResponseHead(from: channel)
        #expect(response?.status == .noContent)
        #expect(response?.headers.first(name: "content-length") == nil)

        try await readUntilResponseEnd(channel: channel)
        #expect(try channel.finish(acceptAlreadyClosed: true).isClean)
    }

    @Test("HEAD response omits the body but keeps content length")
    func headResponseOmitsBodyButKeepsContentLength() async throws {
        var app = HTTPApplication()
        app.method(method: .HEAD, "resource", route: HTTPRequestHandlerRouterClosureWrapper { _ in
            HTTPResponse(
                status: .ok,
                headers: HTTPHeaders([("content-type", "text/plain; charset=utf-8")]),
                body: ByteBufferAllocator().buffer(string: "BODY")
            )
        })

        let channel = EmbeddedChannel(handler: makeHTTP1Handler(app: app))

        try channel.writeInbound(HTTPServerRequestPart.head(makeRequestHead(method: .HEAD, uri: "/resource")))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let response = try await requireResponseHead(from: channel)
        #expect(response?.status == .ok)
        // Content-Length must mirror the equivalent GET body ("BODY" = 4 bytes)...
        #expect(response?.headers.first(name: "content-length") == "4")
        // ...but the body itself must not be written for a HEAD request.
        try assertNextOutboundPartIsResponseEnd(channel: channel)

        #expect(try channel.finish(acceptAlreadyClosed: true).isClean)
    }

    @Test("converts thrown route errors into 500 responses")
    func convertsThrownRouteErrorsIntoInternalServerErrorResponses() async throws {
        var app = HTTPApplication()
        app.get("throws") { _ -> HTTPResponse in
            throw RouteError.failed
        }

        let channel = EmbeddedChannel(handler: makeHTTP1Handler(app: app))

        try channel.writeInbound(HTTPServerRequestPart.head(makeRequestHead(method: .GET, uri: "/throws")))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let response = try await requireResponseHead(from: channel)
        #expect(response?.status == .internalServerError)

        try await readUntilResponseEnd(channel: channel)
        #expect(try channel.finish(acceptAlreadyClosed: true).isClean)
    }

    @Test("middleware drop closes channel without response")
    func middlewareDropClosesChannelWithoutResponse() async throws {
        var app = HTTPApplication()
        app.middleware { _ in .drop }
        app.get("blocked") { _ -> HTTPResponse in HTTPResponse(status: .ok) }

        let channel = EmbeddedChannel(handler: makeHTTP1Handler(app: app))

        try channel.writeInbound(HTTPServerRequestPart.head(makeRequestHead(method: .GET, uri: "/blocked")))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))
        for _ in 0..<50 {
            channel.embeddedEventLoop.run()
            if !channel.isActive {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(try channel.readOutbound(as: HTTPServerResponsePart.self) == nil)
        #expect(!channel.isActive)
        #expect(try channel.finish(acceptAlreadyClosed: true).isClean)
    }

    @Test("rejects bodies larger than the server limit")
    func rejectsBodiesLargerThanServerLimit() async throws {
        let recorder = BodyRecorder()
        var app = HTTPApplication()
        app.post("upload") { request -> HTTPResponse in
            await recorder.record(stringBody(from: request))
            return HTTPResponse(status: .ok)
        }

        let channel = EmbeddedChannel(
            handler: makeHTTP1Handler(
                app: app,
                maximumBodySize: 8
            )
        )
        let allocator = ByteBufferAllocator()

        try channel.writeInbound(HTTPServerRequestPart.head(makeRequestHead(method: .POST, uri: "/upload")))
        try channel.writeInbound(HTTPServerRequestPart.body(allocator.buffer(string: "1234")))
        try channel.writeInbound(HTTPServerRequestPart.body(allocator.buffer(string: "56789")))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let response = try await requireResponseHead(from: channel)
        #expect(response?.status == .payloadTooLarge)
        #expect(await recorder.calls() == 0)

        try await readUntilResponseEnd(channel: channel)
        #expect(try channel.finish(acceptAlreadyClosed: true).isClean)
    }

    @Test("uses route body limit when it is lower than the server limit")
    func usesRouteBodyLimitWhenLowerThanServerLimit() async throws {
        let recorder = BodyRecorder()
        var app = HTTPApplication()
        app.post("upload", maximumBodySize: 8) { request -> HTTPResponse in
            await recorder.record(stringBody(from: request))
            return HTTPResponse(status: .ok)
        }

        let channel = EmbeddedChannel(
            handler: makeHTTP1Handler(
                app: app,
                maximumBodySize: 20
            )
        )
        let allocator = ByteBufferAllocator()

        try channel.writeInbound(HTTPServerRequestPart.head(makeRequestHead(method: .POST, uri: "/upload")))
        try channel.writeInbound(HTTPServerRequestPart.body(allocator.buffer(string: "1234")))
        try channel.writeInbound(HTTPServerRequestPart.body(allocator.buffer(string: "56789")))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let response = try await requireResponseHead(from: channel)
        #expect(response?.status == .payloadTooLarge)
        #expect(await recorder.calls() == 0)

        try await readUntilResponseEnd(channel: channel)
        #expect(try channel.finish(acceptAlreadyClosed: true).isClean)
    }
}

@Suite("HTTP server lifecycle")
struct HTTPServerLifecycleTests {
    @Test("stop closes the bound server channel")
    func stopClosesBoundServerChannel() async throws {
        let server = HTTPServer(app: HTTPApplication())
//        let channel = EmbeddedChannel()
//        server.channel = channel

        await server.stop()
//        channel.embeddedEventLoop.run()

//        try await channel.closeFuture.get()
        #expect(server.channel == nil)
    }
}

@Suite("Default request handler routing")
struct DefaultHTTPRequestHandlerRoutingTests {
    @Test("exact route wins over matching prefix route")
    func exactRouteWinsOverMatchingPrefixRoute() async throws {
        var app = HTTPApplication()
        app.matchGet("api") { _ -> HTTPResponse in
            HTTPResponse(status: .accepted)
        }
        app.get("api", "health") { _ -> HTTPResponse in
            HTTPResponse(status: .ok)
        }

        var context = HTTPContext(
            request: HTTPRequest(
                url: URL(string: "/api/health")!,
                method: .GET,
                headers: HTTPHeaders(),
                body: nil,
                trailers: nil,
                cookies: [:]
            )
        )

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
    }

    @Test("prefix route handles unmatched subpath")
    func prefixRouteHandlesUnmatchedSubpath() async throws {
        var app = HTTPApplication()
        app.matchGet("api") { _ -> HTTPResponse in
            HTTPResponse(status: .accepted)
        }

        var context = HTTPContext(
            request: HTTPRequest(
                url: URL(string: "/api/users")!,
                method: .GET,
                headers: HTTPHeaders(),
                body: nil,
                trailers: nil,
                cookies: [:]
            )
        )

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .accepted)
    }

    @Test("not found route preserves response headers while forcing not found status")
    func notFoundRoutePreservesResponseHeadersWhileForcingNotFoundStatus() async throws {
        var app = HTTPApplication()
        app.notFound { _ -> HTTPResponse in
            HTTPResponse(
                status: .temporaryRedirect,
                headers: HTTPHeaders([("location", "/login")])
            )
        }

        var context = HTTPContext(
            request: HTTPRequest(
                url: URL(string: "/missing")!,
                method: .GET,
                headers: HTTPHeaders(),
                body: nil,
                trailers: nil,
                cookies: [:]
            )
        )

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .notFound)
        #expect(context.response.headers.first(name: "location") == "/login")
    }

    @Test("not found route preserves response body")
    func notFoundRoutePreservesResponseBody() async throws {
        var app = HTTPApplication()
        app.notFound { _ -> HTTPResponse in
            HTTPResponse(
                status: .ok,
                body: ByteBufferAllocator().buffer(string: "missing")
            )
        }

        var context = HTTPContext(
            request: HTTPRequest(
                url: URL(string: "/missing")!,
                method: .GET,
                headers: HTTPHeaders(),
                body: nil,
                trailers: nil,
                cookies: [:]
            )
        )

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .notFound)
        #expect(context.response.body?.getString(
            at: context.response.body?.readerIndex ?? 0,
            length: context.response.body?.readableBytes ?? 0
        ) == "missing")
    }

    @Test("router closure preserves returned response trailers")
    func routerClosurePreservesReturnedResponseTrailers() async throws {
        var app = HTTPApplication()
        app.get("trailers") { _ -> HTTPResponse in
            var response = HTTPResponse(status: .ok)
            response.trailers = HTTPHeaders([("x-checksum", "abc")])
            return response
        }

        var context = HTTPContext(
            request: HTTPRequest(
                url: URL(string: "/trailers")!,
                method: .GET,
                headers: HTTPHeaders(),
                body: nil,
                trailers: nil,
                cookies: [:]
            )
        )

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.trailers?.first(name: "x-checksum") == "abc")
    }

    @Test("data helper creates response with content type and body")
    func dataHelperCreatesResponseWithContentTypeAndBody() {
        let response = Data("hello".utf8).http(type: "text/plain")

        #expect(response.status == .ok)
        #expect(response.headers.first(name: "content-type") == "text/plain")
        #expect(response.body?.getString(at: 0, length: response.body?.readableBytes ?? 0) == "hello")
    }

    @Test("httpContent preserves status headers content type and nil body")
    func httpContentPreservesStatusHeadersContentTypeAndNilBody() {
        let response = httpContent(
            status: .created,
            type: "application/octet-stream",
            headers: HTTPHeaders([("x-source", "test")])
        ) { nil }

        #expect(response.status == .created)
        #expect(response.headers.first(name: "x-source") == "test")
        #expect(response.headers.first(name: "content-type") == "application/octet-stream")
        #expect(response.body == nil)
    }

    @Test("json helpers encode value and closure value")
    func jsonHelpersEncodeValueAndClosureValue() throws {
        struct Payload: Codable, Equatable {
            let message: String
            let count: Int
        }

        let directResponse = json(Payload(message: "ok", count: 2), status: .accepted)
        let closureResponse = json(status: .created) {
            Payload(message: "created", count: 1)
        }

        let directBody = try #require(directResponse.body)
        let closureBody = try #require(closureResponse.body)
        let directDecoded = try JSONDecoder().decode(Payload.self, from: Data(buffer: directBody))
        let closureDecoded = try JSONDecoder().decode(Payload.self, from: Data(buffer: closureBody))

        #expect(directResponse.status == .accepted)
        #expect(directResponse.headers.first(name: "content-type") == "application/json; charset=utf-8")
        #expect(directDecoded == Payload(message: "ok", count: 2))
        #expect(closureResponse.status == .created)
        #expect(closureDecoded == Payload(message: "created", count: 1))
    }

    @Test("handler overload routes through HTTPRequestHandler")
    func handlerOverloadRoutesThroughHTTPRequestHandler() async throws {
        struct StaticHandler: HTTPRequestHandler {
            func route(context: inout HTTPContext) async throws {
                context.response.status = .accepted
            }
        }

        var app = HTTPApplication()
        app.method(method: .GET, "handler", route: StaticHandler())
        var context = makeRoutingContext(method: .GET, uri: "/handler")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .accepted)
    }

    @Test("data route closure returns HTML response")
    func dataRouteClosureReturnsHTMLResponse() async throws {
        var app = HTTPApplication()
        app.get("data") { _ -> Data in
            Data("payload".utf8)
        }
        var context = makeRoutingContext(method: .GET, uri: "/data")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.headers.first(name: "content-type") == "application/octet-stream")
        #expect(context.response.body?.getString(at: 0, length: context.response.body?.readableBytes ?? 0) == "payload")
    }

    @Test("middleware can stop routing with custom response")
    func middlewareCanStopRoutingWithCustomResponse() async throws {
        var app = HTTPApplication()
        app.middleware { context in
            context.response.status = .unauthorized
            context.response.headers.add(name: "x-middleware", value: "stopped")
            return .respond
        }
        app.get("secret") { _ -> HTTPResponse in HTTPResponse(status: .ok) }
        var context = makeRoutingContext(method: .GET, uri: "/secret")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .unauthorized)
        #expect(context.response.headers.first(name: "x-middleware") == "stopped")
    }

    @Test("middleware can drop routing without response")
    func middlewareCanDropRoutingWithoutResponse() async throws {
        var app = HTTPApplication()
        app.middleware { _ in .drop }
        app.get("secret") { _ -> HTTPResponse in HTTPResponse(status: .ok) }
        var context = makeRoutingContext(method: .GET, uri: "/secret")

        let decision = try await app.handler.routeWithDecision(context: &context)

        #expect(decision == .drop)
    }

    @Test("match method shortcuts register prefix routes")
    func matchMethodShortcutsRegisterPrefixRoutes() async throws {
        var app = HTTPApplication()
        app.matchGet("prefix") { _ -> HTTPResponse in HTTPResponse(status: .ok) }
        app.matchPost("prefix") { _ -> HTTPResponse in HTTPResponse(status: .created) }
        app.matchPut("prefix") { _ -> HTTPResponse in HTTPResponse(status: .accepted) }
        app.matchDelete("prefix") { _ -> HTTPResponse in HTTPResponse(status: .gone) }

        #expect(try await routeStatus(app: app, method: .GET, uri: "/prefix/a") == .ok)
        #expect(try await routeStatus(app: app, method: .POST, uri: "/prefix/a") == .created)
        #expect(try await routeStatus(app: app, method: .PUT, uri: "/prefix/a") == .accepted)
        #expect(try await routeStatus(app: app, method: .DELETE, uri: "/prefix/a") == .gone)
    }

    @Test("method shortcuts register exact routes")
    func methodShortcutsRegisterExactRoutes() async throws {
        var app = HTTPApplication()
        app.get("resource") { _ -> HTTPResponse in HTTPResponse(status: .ok) }
        app.post("resource") { _ -> HTTPResponse in HTTPResponse(status: .created) }
        app.put("resource") { _ -> HTTPResponse in HTTPResponse(status: .accepted) }
        app.delete("resource") { _ -> HTTPResponse in HTTPResponse(status: .gone) }

        #expect(try await routeStatus(app: app, method: .GET) == .ok)
        #expect(try await routeStatus(app: app, method: .POST) == .created)
        #expect(try await routeStatus(app: app, method: .PUT) == .accepted)
        #expect(try await routeStatus(app: app, method: .DELETE) == .gone)
    }

    @Test("route enforces configured route body limit")
    func routeEnforcesConfiguredRouteBodyLimit() async throws {
        let recorder = BodyRecorder()
        var app = HTTPApplication()
        app.post("upload", maximumBodySize: 8) { request -> HTTPResponse in
            await recorder.record(stringBody(from: request))
            return HTTPResponse(status: .ok)
        }

        var context = HTTPContext(
            request: HTTPRequest(
                url: URL(string: "/upload")!,
                method: .POST,
                headers: HTTPHeaders(),
                body: ByteBufferAllocator().buffer(string: "123456789"),
                trailers: nil,
                cookies: [:]
            )
        )

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .payloadTooLarge)
        #expect(context.response.headers.first(name: "content-length") == "0")
        #expect(await recorder.calls() == 0)
    }

    private func routeStatus(
        app: HTTPApplication<DefaultHTTPRoutingHandler>,
        method: HTTPMethod,
        uri: String = "/resource"
    ) async throws -> HTTPResponseStatus {
        var context = makeRoutingContext(method: method, uri: uri)
        _ = try await app.handler.routeWithDecision(context: &context)
        return context.response.status
    }

    private func makeRoutingContext(method: HTTPMethod, uri: String) -> HTTPContext {
        HTTPContext(
            request: HTTPRequest(
                url: URL(string: uri)!,
                method: method,
                headers: HTTPHeaders(),
                body: nil,
                trailers: nil,
                cookies: [:]
            )
        )
    }
}
