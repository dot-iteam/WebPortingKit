import Foundation
import NIOCore
import NIOHTTP1
import Testing
@testable import WebPortingKit

@Suite("Public response helpers")
struct PublicResponseHelperTests {
    private struct Payload: Codable, Equatable {
        let message: String
        let count: Int
    }

    @Test("data helper creates HTML response by default")
    func dataHelperCreatesHTMLResponseByDefault() throws {
        let response = Data("hello".utf8).http(type: "text/html; charset=utf-8")

        #expect(response.status == .ok)
        #expect(response.headers.first(name: "content-type") == "text/html; charset=utf-8")
        #expect(response.body?.getString(at: 0, length: response.body?.readableBytes ?? 0) == "hello")
    }

    @Test("data helper accepts custom content type")
    func dataHelperAcceptsCustomContentType() {
        let response = Data("plain".utf8).http(type: "text/plain")

        #expect(response.headers.first(name: "content-type") == "text/plain")
    }

    @Test("httpContent preserves status headers and content type")
    func httpContentPreservesStatusHeadersAndContentType() {
        let response = httpContent(
            status: .created,
            type: "application/octet-stream",
            headers: HTTPHeaders([("x-source", "test")])
        ) {
            Data([0x01, 0x02, 0x03])
        }

        #expect(response.status == .created)
        #expect(response.headers.first(name: "x-source") == "test")
        #expect(response.headers.first(name: "content-type") == "application/octet-stream")
        #expect(response.body?.readableBytes == 3)
    }

    @Test("httpContent allows nil data")
    func httpContentAllowsNilData() {
        let response = httpContent(type: "text/plain") { nil }

        #expect(response.status == .ok)
        #expect(response.headers.first(name: "content-type") == "text/plain")
        #expect(response.body == nil)
    }

    @Test("json helper encodes value and sets JSON content type")
    func jsonHelperEncodesValueAndSetsJSONContentType() throws {
        let response = json(Payload(message: "ok", count: 2), status: .accepted)
        let body = try #require(response.body)
        let decoded = try JSONDecoder().decode(Payload.self, from: Data(buffer: body))

        #expect(response.status == .accepted)
        #expect(response.headers.first(name: "content-type") == "application/json; charset=utf-8")
        #expect(decoded == Payload(message: "ok", count: 2))
    }

    @Test("redirect initializer sets status and location")
    func redirectInitializerSetsStatusAndLocation() {
        let response = HTTPResponse(redirect: "/login", status: .temporaryRedirect)

        #expect(response.status == .temporaryRedirect)
        #expect(response.headers.first(name: "location") == "/login")
        #expect(response.body == nil)
    }

    @Test("redirect mutator replaces status and location")
    func redirectMutatorReplacesStatusAndLocation() {
        var response = HTTPResponse(
            status: .ok,
            headers: HTTPHeaders([("location", "/old")]),
            body: nil
        )

        response.redirect(to: "/new", status: .seeOther)

        #expect(response.status == .seeOther)
        #expect(response.headers.first(name: "location") == "/new")
    }

    @Test("location header helper adds location")
    func locationHeaderHelperAddsLocation() {
        var headers = HTTPHeaders()

        headers.add(location: "/target")

        #expect(headers.first(name: "location") == "/target")
    }

    @Test("json closure helper encodes returned value")
    func jsonClosureHelperEncodesReturnedValue() throws {
        let response = json(status: .created) {
            Payload(message: "created", count: 1)
        }
        let body = try #require(response.body)
        let decoded = try JSONDecoder().decode(Payload.self, from: Data(buffer: body))

        #expect(response.status == .created)
        #expect(decoded == Payload(message: "created", count: 1))
    }
}

@Suite("Public request helpers")
struct PublicRequestHelperTests {
    private struct Profile: Codable, Equatable {
        let name: String
        let age: Int
    }

    @Test("request exposes path normalized path and URL components")
    mutating func requestExposesPathNormalizedPathAndURLComponents() {
        let request = HTTPRequest(
            url: URL(string: "/Users/Profile?tab=Info")!,
            method: .GET,
            headers: HTTPHeaders(),
            body: nil,
            trailers: nil,
            cookies: [:]
        )

        #expect(request.path == ["/", "Users", "Profile"])
        #expect(request.normalizedPath == ["/", "users", "profile"])
        #expect(request.urlComponents.queryItems?.first?.name == "tab")
        #expect(request.urlComponents.queryItems?.first?.value == "Info")
    }

    @Test("getBody returns raw data when content type is missing")
    func getBodyReturnsRawDataWhenContentTypeIsMissing() throws {
        let request = makeRequest(contentType: nil, body: "raw-body")

        guard case .data(let data) = request.getBody(type: Profile.self) else {
            Issue.record("Expected raw data body")
            return
        }
        #expect(String(decoding: try #require(data), as: UTF8.self) == "raw-body")
    }

    @Test("getBody callback receives decoded form body")
    func getBodyCallbackReceivesDecodedFormBody() throws {
        let request = makeRequest(
            contentType: "application/x-www-form-urlencoded",
            body: "name=Abdul&age=31"
        )
        var decoded: Profile?

        request.getBody(type: Profile.self) { body in
            guard case .object(let value) = body else { return }
            decoded = value
        }

        #expect(decoded == Profile(name: "Abdul", age: 31))
    }

    @Test("malformed JSON decodes to nil object")
    func malformedJSONDecodesToNilObject() {
        let request = makeRequest(contentType: "application/json", body: "{bad-json")

        guard case .object(let decoded) = request.getBody(type: Profile.self) else {
            Issue.record("Expected object body")
            return
        }
        #expect(decoded == nil)
        #expect(request.getDecodedBody(type: Profile.self) == nil)
    }

    @Test("getDecodedForm returns nil form for raw data")
    func getDecodedFormReturnsNilFormForRawData() {
        let request = makeRequest(contentType: "application/octet-stream", body: "raw")
        let decoded: DecodedMultipartForm<Profile> = request.getDecodedForm(type: Profile.self)

        #expect(decoded.files.isEmpty)
        #expect(decoded.form == nil)
    }

    private func makeRequest(contentType: String?, body: String) -> HTTPRequest {
        var headers = HTTPHeaders()
        if let contentType {
            headers.add(name: "content-type", value: contentType)
        }
        return HTTPRequest(
            url: URL(string: "/profile")!,
            method: .POST,
            headers: headers,
            body: ByteBufferAllocator().buffer(string: body),
            trailers: nil,
            cookies: [:]
        )
    }
}

@Suite("Public routing APIs")
struct PublicRoutingAPITests {
    struct StaticHandler: HTTPRequestHandler {
        let status: HTTPResponseStatus

        func route(context: inout HTTPContext) async throws {
            context.response.status = status
        }
    }

    @Test("method shortcuts register exact routes for supported methods")
    func methodShortcutsRegisterExactRoutesForSupportedMethods() async throws {
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

    @Test("handler overload routes through HTTPRequestHandler")
    func handlerOverloadRoutesThroughHTTPRequestHandler() async throws {
        var app = HTTPApplication()
        app.method(method: .GET, "handler", route: StaticHandler(status: .accepted))

        let status = try await routeStatus(app: app, method: .GET, uri: "/handler")

        #expect(status == .accepted)
    }

    @Test("data route closure returns HTML data response")
    func dataRouteClosureReturnsHTMLDataResponse() async throws {
        var app = HTTPApplication()
        app.get("data") { _ -> HTTPResponse in Data("payload".utf8).http(type: "text/html; charset=utf-8") }
        var context = makeContext(method: .GET, uri: "/data")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.headers.first(name: "content-type") == "text/html; charset=utf-8")
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
        var context = makeContext(method: .GET, uri: "/secret")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .unauthorized)
        #expect(context.response.headers.first(name: "x-middleware") == "stopped")
    }

    @Test("middleware can drop routing without response")
    func middlewareCanDropRoutingWithoutResponse() async throws {
        var app = HTTPApplication()
        app.middleware { _ in .drop }
        app.get("secret") { _ -> HTTPResponse in HTTPResponse(status: .ok) }
        var context = makeContext(method: .GET, uri: "/secret")

        let decision = try await app.handler.routeWithDecision(context: &context)

        #expect(decision == .drop)
    }

    @Test("static files serves files from registered location")
    func staticFilesServesFilesFromRegisteredLocation() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("hello static".utf8).write(to: directory.appendingPathComponent("hello.txt"))

        var app = HTTPApplication()
        app.staticFiles("assets", location: directory)
        var context = makeContext(method: .GET, uri: "/assets/hello.txt")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.headers.first(name: "content-type") == "text/plain; charset=utf-8")
        #expect(context.response.body?.getString(at: 0, length: context.response.body?.readableBytes ?? 0) == "hello static")
    }

    @Test("static file helper can be used inside match route")
    func staticFileHelperCanBeUsedInsideMatchRoute() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("from helper".utf8).write(to: directory.appendingPathComponent("script.js"))

        var app = HTTPApplication()
        app.matchGet("files") { request in
            await staticFile(request: request, from: directory, pathPrefix: ["files"])
        }
        var context = makeContext(method: .GET, uri: "/files/script.js")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.headers.first(name: "content-type") == "application/javascript; charset=utf-8")
        #expect(context.response.body?.getString(at: 0, length: context.response.body?.readableBytes ?? 0) == "from helper")
    }

    @Test("static files includes cache validators")
    func staticFilesIncludesCacheValidators() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("cache.txt")
        let lastModified = Date(timeIntervalSince1970: 1_700_000_000)
        try Data("cacheable".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: lastModified], ofItemAtPath: fileURL.path)

        var app = HTTPApplication()
        app.staticFiles("assets", location: directory)
        var context = makeContext(method: .GET, uri: "/assets/cache.txt")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.headers.first(name: "last-modified") == httpDateString(lastModified))
        #expect(context.response.headers.first(name: "cache-control") == "public, max-age=0, must-revalidate")
        #expect(context.response.body?.getString(at: 0, length: context.response.body?.readableBytes ?? 0) == "cacheable")
    }

    @Test("static files returns not modified for fresh conditional requests")
    func staticFilesReturnsNotModifiedForFreshConditionalRequests() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("cache.txt")
        let lastModified = Date(timeIntervalSince1970: 1_700_000_000)
        try Data("cacheable".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: lastModified], ofItemAtPath: fileURL.path)

        var headers = HTTPHeaders()
        headers.add(name: "if-modified-since", value: httpDateString(lastModified))
        var app = HTTPApplication()
        app.staticFiles("assets", location: directory)
        var context = makeContext(method: .GET, uri: "/assets/cache.txt", headers: headers)

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .notModified)
        #expect(context.response.headers.first(name: "last-modified") == httpDateString(lastModified))
        #expect(context.response.headers.first(name: "cache-control") == "public, max-age=0, must-revalidate")
        #expect(context.response.headers.first(name: "content-type") == nil)
        #expect(context.response.body == nil)
    }

    @Test("static files serves body for stale conditional requests")
    func staticFilesServesBodyForStaleConditionalRequests() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("cache.txt")
        let lastModified = Date(timeIntervalSince1970: 1_700_000_000)
        try Data("fresh body".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: lastModified], ofItemAtPath: fileURL.path)

        var headers = HTTPHeaders()
        headers.add(name: "if-modified-since", value: httpDateString(lastModified.addingTimeInterval(-1)))
        var app = HTTPApplication()
        app.staticFiles("assets", location: directory)
        var context = makeContext(method: .GET, uri: "/assets/cache.txt", headers: headers)

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.body?.getString(at: 0, length: context.response.body?.readableBytes ?? 0) == "fresh body")
    }

    @Test("static files uses default MIME types for common assets")
    func staticFilesUsesDefaultMIMETypesForCommonAssets() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([0x00, 0x01]).write(to: directory.appendingPathComponent("font.WOFF2"))
        try Data("%PDF".utf8).write(to: directory.appendingPathComponent("document.pdf"))

        var app = HTTPApplication()
        app.staticFiles("assets", location: directory)

        var fontContext = makeContext(method: .GET, uri: "/assets/font.WOFF2")
        _ = try await app.handler.routeWithDecision(context: &fontContext)
        #expect(fontContext.response.status == .ok)
        #expect(fontContext.response.headers.first(name: "content-type") == "font/woff2")

        var pdfContext = makeContext(method: .GET, uri: "/assets/document.pdf")
        _ = try await app.handler.routeWithDecision(context: &pdfContext)
        #expect(pdfContext.response.status == .ok)
        #expect(pdfContext.response.headers.first(name: "content-type") == "application/pdf")
    }

    @Test("static files accepts custom MIME type registry")
    func staticFilesAcceptsCustomMIMETypeRegistry() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("asset".utf8).write(to: directory.appendingPathComponent("bundle.customasset"))

        var mimeTypes = HTTPMimeTypeRegistry.default
        mimeTypes.register("application/x-custom-asset", for: ".customasset")

        var app = HTTPApplication()
        app.staticFiles("assets", location: directory, mimeTypes: mimeTypes)
        var context = makeContext(method: .GET, uri: "/assets/bundle.customasset")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.headers.first(name: "content-type") == "application/x-custom-asset")
    }

    @Test("static file helper accepts custom fallback MIME type")
    func staticFileHelperAcceptsCustomFallbackMIMEType() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("unknown".utf8).write(to: directory.appendingPathComponent("file.unknownext"))
        let request = HTTPRequest(
            url: URL(string: "/files/file.unknownext")!,
            method: .GET,
            headers: HTTPHeaders(),
            body: nil,
            trailers: nil,
            cookies: [:]
        )

        let response = await staticFile(
            request: request,
            from: directory,
            pathPrefix: ["files"],
            defaultMimeType: "application/x-fallback"
        )

        #expect(response.status == .ok)
        #expect(response.headers.first(name: "content-type") == "application/x-fallback")
    }

    @Test("embedded resource helper serves explicit resource inside GET route")
    func embeddedResourceHelperServesExplicitResourceInsideGETRoute() async throws {
        let resource = EmbeddedHTTPResource(
            id: "styles/app.css",
            mimeType: "text/css; charset=utf-8",
            data: { Data("body { color: black; }".utf8) }
        )
        var app = HTTPApplication()
        app.get("assets", "styles", "app.css") { request in
            await embeddedResource(request: request, resource: resource)
        }
        var context = makeContext(method: .GET, uri: "/assets/styles/app.css")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.headers.first(name: "content-type") == "text/css; charset=utf-8")
        #expect(context.response.headers.first(name: "last-modified") != nil)
        #expect(context.response.headers.first(name: "etag") == nil)
        #expect(context.response.headers.first(name: "cache-control") == "public, max-age=0, must-revalidate")
        #expect(context.response.body?.getString(at: 0, length: context.response.body?.readableBytes ?? 0) == "body { color: black; }")
    }

    @Test("embedded resource helper accepts non string cache identity")
    func embeddedResourceHelperAcceptsNonStringCacheIdentity() async throws {
        enum AssetID: Hashable, Sendable {
            case css
        }

        let metadataStore = EmbeddedResourceMetadataStore()
        var app = HTTPApplication()
        app.get("assets", "typed.css") { request in
            await embeddedResource(
                request: request,
                id: AssetID.css,
                mimeType: "text/css; charset=utf-8",
                data: { Data("main { display: block; }".utf8) },
                metadataStore: metadataStore
            )
        }

        var firstContext = makeContext(method: .GET, uri: "/assets/typed.css")
        _ = try await app.handler.routeWithDecision(context: &firstContext)
        let lastModified = try #require(firstContext.response.headers.first(name: "last-modified"))

        var headers = HTTPHeaders()
        headers.add(name: "if-modified-since", value: lastModified)
        var secondContext = makeContext(method: .GET, uri: "/assets/typed.css", headers: headers)
        _ = try await app.handler.routeWithDecision(context: &secondContext)

        #expect(secondContext.response.status == .notModified)
        #expect(secondContext.response.headers.first(name: "last-modified") == lastModified)
        #expect(secondContext.response.body == nil)
    }

    @Test("embedded resource helper returns not modified for fresh conditional requests")
    func embeddedResourceHelperReturnsNotModifiedForFreshConditionalRequests() async throws {
        let metadataStore = EmbeddedResourceMetadataStore()
        let resource = EmbeddedHTTPResource(
            id: "site.js",
            mimeType: "application/javascript; charset=utf-8",
            data: { Data("console.log('ok')".utf8) }
        )
        var app = HTTPApplication()
        app.get("assets", "site.js") { request in
            await embeddedResource(request: request, resource: resource, metadataStore: metadataStore)
        }

        var firstContext = makeContext(method: .GET, uri: "/assets/site.js")
        _ = try await app.handler.routeWithDecision(context: &firstContext)
        let lastModified = try #require(firstContext.response.headers.first(name: "last-modified"))

        var headers = HTTPHeaders()
        headers.add(name: "if-modified-since", value: lastModified)
        var secondContext = makeContext(method: .GET, uri: "/assets/site.js", headers: headers)
        _ = try await app.handler.routeWithDecision(context: &secondContext)

        #expect(secondContext.response.status == .notModified)
        #expect(secondContext.response.headers.first(name: "last-modified") == lastModified)
        #expect(secondContext.response.body == nil)
    }

    @Test("embedded resource helper omits ETag by default")
    func embeddedResourceHelperOmitsETagByDefault() async throws {
        var app = HTTPApplication()
        app.get("assets", "plain.txt") { request in
            await embeddedResource(
                request: request,
                id: "plain.txt",
                mimeType: "text/plain; charset=utf-8",
                data: { Data("plain".utf8) }
            )
        }

        var context = makeContext(method: .GET, uri: "/assets/plain.txt")
        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.headers.first(name: "etag") == nil)
    }

    @Test("embedded resource helper caches custom ETag algorithm result")
    func embeddedResourceHelperCachesCustomETagAlgorithmResult() async throws {
        let metadataStore = EmbeddedResourceMetadataStore()
        final class Counter: @unchecked Sendable {
            var count = 0
        }
        let counter = Counter()
        let algorithm = HTTPETagSource.generated(name: "length", cache: true) { data in
            counter.count += 1
            return "\"length-\(data.count)\""
        }

        var app = HTTPApplication()
        app.get("assets", "custom.txt") { request in
            await embeddedResource(
                request: request,
                id: "custom.txt",
                mimeType: "text/plain; charset=utf-8",
                data: { Data("cached".utf8) },
                metadataStore: metadataStore,
                eTag: algorithm
            )
        }

        var firstContext = makeContext(method: .GET, uri: "/assets/custom.txt")
        _ = try await app.handler.routeWithDecision(context: &firstContext)
        var secondContext = makeContext(method: .GET, uri: "/assets/custom.txt")
        _ = try await app.handler.routeWithDecision(context: &secondContext)

        #expect(firstContext.response.headers.first(name: "etag") == "\"length-6\"")
        #expect(secondContext.response.headers.first(name: "etag") == "\"length-6\"")
        #expect(counter.count == 1)
    }

    @Test("embedded resource helper can disable generated ETag caching")
    func embeddedResourceHelperCanDisableGeneratedETagCaching() async throws {
        let metadataStore = EmbeddedResourceMetadataStore()
        final class Counter: @unchecked Sendable {
            var count = 0
        }
        let counter = Counter()
        let algorithm = HTTPETagSource.generated(name: "uncached-length", cache: false) { data in
            counter.count += 1
            return "\"uncached-length-\(data.count)\""
        }

        var app = HTTPApplication()
        app.get("assets", "uncached.txt") { request in
            await embeddedResource(
                request: request,
                id: "uncached.txt",
                mimeType: "text/plain; charset=utf-8",
                data: { Data("uncached".utf8) },
                metadataStore: metadataStore,
                eTag: algorithm
            )
        }

        var firstContext = makeContext(method: .GET, uri: "/assets/uncached.txt")
        _ = try await app.handler.routeWithDecision(context: &firstContext)
        var secondContext = makeContext(method: .GET, uri: "/assets/uncached.txt")
        _ = try await app.handler.routeWithDecision(context: &secondContext)

        #expect(firstContext.response.headers.first(name: "etag") == "\"uncached-length-8\"")
        #expect(secondContext.response.headers.first(name: "etag") == "\"uncached-length-8\"")
        #expect(counter.count == 2)
    }

    @Test("embedded resource helper accepts constant ETag without reading data for validation")
    func embeddedResourceHelperAcceptsConstantETagWithoutReadingDataForValidation() async throws {
        final class Counter: @unchecked Sendable {
            var count = 0
        }
        let counter = Counter()
        var app = HTTPApplication()
        app.get("assets", "constant.txt") { request in
            await embeddedResource(
                request: request,
                id: "constant.txt",
                mimeType: "text/plain; charset=utf-8",
                data: {
                    counter.count += 1
                    return Data("constant".utf8)
                },
                eTag: .constant("\"constant-version\"")
            )
        }

        var firstContext = makeContext(method: .GET, uri: "/assets/constant.txt")
        _ = try await app.handler.routeWithDecision(context: &firstContext)

        var headers = HTTPHeaders()
        headers.add(name: "if-none-match", value: "\"constant-version\"")
        var secondContext = makeContext(method: .GET, uri: "/assets/constant.txt", headers: headers)
        _ = try await app.handler.routeWithDecision(context: &secondContext)

        #expect(firstContext.response.headers.first(name: "etag") == "\"constant-version\"")
        #expect(secondContext.response.status == .notModified)
        #expect(secondContext.response.headers.first(name: "etag") == "\"constant-version\"")
        #expect(secondContext.response.body == nil)
        #expect(counter.count == 1)
    }

    @Test("embedded resource helper returns not modified for matching ETag")
    func embeddedResourceHelperReturnsNotModifiedForMatchingETag() async throws {
        let metadataStore = EmbeddedResourceMetadataStore()
        let resource = EmbeddedHTTPResource(
            id: "site.css",
            mimeType: "text/css; charset=utf-8",
            eTag: .constant("\"site-css-v1\""),
            data: { Data("html { color-scheme: light; }".utf8) }
        )
        var app = HTTPApplication()
        app.get("assets", "site.css") { request in
            await embeddedResource(request: request, resource: resource, metadataStore: metadataStore)
        }

        var firstContext = makeContext(method: .GET, uri: "/assets/site.css")
        _ = try await app.handler.routeWithDecision(context: &firstContext)
        let lastModified = try #require(firstContext.response.headers.first(name: "last-modified"))
        let eTag = try #require(firstContext.response.headers.first(name: "etag"))

        var headers = HTTPHeaders()
        headers.add(name: "if-none-match", value: eTag)
        var secondContext = makeContext(method: .GET, uri: "/assets/site.css", headers: headers)
        _ = try await app.handler.routeWithDecision(context: &secondContext)

        #expect(secondContext.response.status == .notModified)
        #expect(secondContext.response.headers.first(name: "last-modified") == lastModified)
        #expect(secondContext.response.headers.first(name: "etag") == eTag)
        #expect(secondContext.response.body == nil)
    }

    @Test("embedded resource helper gives ETag precedence over stale last modified")
    func embeddedResourceHelperGivesETagPrecedenceOverStaleLastModified() async throws {
        let metadataStore = EmbeddedResourceMetadataStore()
        let resource = EmbeddedHTTPResource(
            id: "site-font",
            mimeType: "font/woff2",
            eTag: .constant("\"site-font-v1\""),
            data: { Data([0x77, 0x4f, 0x46, 0x32]) }
        )
        var app = HTTPApplication()
        app.get("assets", "site.woff2") { request in
            await embeddedResource(request: request, resource: resource, metadataStore: metadataStore)
        }

        var firstContext = makeContext(method: .GET, uri: "/assets/site.woff2")
        _ = try await app.handler.routeWithDecision(context: &firstContext)
        let lastModified = try #require(firstContext.response.headers.first(name: "last-modified"))

        var headers = HTTPHeaders()
        headers.add(name: "if-none-match", value: "\"different\"")
        headers.add(name: "if-modified-since", value: lastModified)
        var secondContext = makeContext(method: .GET, uri: "/assets/site.woff2", headers: headers)
        _ = try await app.handler.routeWithDecision(context: &secondContext)

        #expect(secondContext.response.status == .ok)
        #expect(secondContext.response.body?.readableBytes == 4)
    }

    @Test("embedded resource helper only serves explicitly registered GET route")
    func embeddedResourceHelperOnlyServesExplicitlyRegisteredGETRoute() async throws {
        let resource = EmbeddedHTTPResource(
            id: "secret.txt",
            mimeType: "text/plain; charset=utf-8",
            data: { Data("secret".utf8) }
        )
        var app = HTTPApplication()
        app.get("assets", "secret.txt") { request in
            await embeddedResource(request: request, resource: resource)
        }
        var context = makeContext(method: .GET, uri: "/assets/%2e%2e/secret.txt")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .notFound)
        #expect(context.response.body == nil)
    }

    @Test("static files reject parent directory navigation")
    func staticFilesRejectParentDirectoryNavigation() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parentSecret = directory.deletingLastPathComponent().appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: parentSecret)
        defer { try? FileManager.default.removeItem(at: parentSecret) }

        var app = HTTPApplication()
        app.staticFiles("assets", location: directory)
        var context = makeContext(method: .GET, uri: "/assets/%2e%2e/secret.txt")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .notFound)
        #expect(context.response.body == nil)
    }

    @Test("static files reject encoded slash path components")
    func staticFilesRejectEncodedSlashPathComponents() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var app = HTTPApplication()
        app.staticFiles("assets", location: directory)
        var context = makeContext(method: .GET, uri: "/assets/nested%2ffile.txt")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .notFound)
    }

    @Test("static files do not serve directories")
    func staticFilesDoNotServeDirectories() async throws {
        let directory = try makeTemporaryStaticDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("folder"), withIntermediateDirectories: false)

        var app = HTTPApplication()
        app.staticFiles("assets", location: directory)
        var context = makeContext(method: .GET, uri: "/assets/folder")

        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .notFound)
    }

    @Test("match method shortcuts register prefix routes for supported methods")
    func matchMethodShortcutsRegisterPrefixRoutesForSupportedMethods() async throws {
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

    private func routeStatus(
        app: HTTPApplication<DefaultHTTPRoutingHandler>,
        method: HTTPMethod,
        uri: String = "/resource"
    ) async throws -> HTTPResponseStatus {
        var context = makeContext(method: method, uri: uri)
        _ = try await app.handler.routeWithDecision(context: &context)
        return context.response.status
    }

    private func makeContext(method: HTTPMethod, uri: String, headers: HTTPHeaders = HTTPHeaders()) -> HTTPContext {
        HTTPContext(
            request: HTTPRequest(
                url: URL(string: uri)!,
                method: method,
                headers: headers,
                body: nil,
                trailers: nil,
                cookies: [:]
            )
        )
    }

    private func httpDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    private func makeTemporaryStaticDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebPortingKitStaticTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

@Suite("Public cookie APIs")
struct PublicCookieAPITests {
    @Test("cookie options expose serialized strings")
    func cookieOptionsExposeSerializedStrings() {
        #expect(CookieOption.httpOnly.appendString == "; HttpOnly")
        #expect(CookieOption.secure.appendString == "; Secure")
        #expect(CookieOption.sameSite(.strict).appendString == "; SameSite=Strict")
        #expect(CookieOption.partitioned.appendString == "; Partitioned")
    }

    @Test("cookie option array serializes in order")
    func cookieOptionArraySerializesInOrder() {
        let options: [CookieOption] = [.path("/"), .maxAge(10), .sameSite(.lax), .secure]

        #expect(options.appendString == "; Path=/; Max-Age=10; SameSite=Lax; Secure")
    }

    @Test("negative max age is clamped to zero")
    func negativeMaxAgeIsClampedToZero() {
        var headers = HTTPHeaders()

        headers.add(cookie: ResponseCookie(name: "expired", value: "yes", options: .maxAge(-5)))

        #expect(headers.first(name: "Set-Cookie") == "expired=yes; Max-Age=0")
    }
}
