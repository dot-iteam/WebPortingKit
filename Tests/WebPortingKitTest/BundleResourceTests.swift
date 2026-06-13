import Foundation
import NIOCore
import NIOHTTP1
import Testing
@testable import WebPortingKit

@Suite("Bundle resource helper")
struct BundleResourceTests {
    private func makeRequest(uri: String, headers: HTTPHeaders = HTTPHeaders()) -> HTTPRequest {
        HTTPRequest(
            url: URL(string: uri)!,
            method: .GET,
            headers: headers,
            body: nil,
            trailers: nil,
            cookies: [:]
        )
    }

    @Test("serves a packaged resource and reuses the default MIME fallback")
    func servesPackagedResource() async throws {
        let request = makeRequest(uri: "/assets/localhost.pem")

        let response = await bundleResource(request: request, in: .module, pathPrefix: ["assets"])

        #expect(response.status == .ok)
        // .pem is not in the default registry, so it falls back to octet-stream.
        #expect(response.headers.first(name: "content-type") == "application/octet-stream")

        let resourceURL = try #require(Bundle.module.url(forResource: "localhost", withExtension: "pem"))
        let expected = try Data(contentsOf: resourceURL)
        #expect(response.body?.readableBytes == expected.count)
    }

    @Test("includes cache validators for packaged resources")
    func includesCacheValidators() async throws {
        let request = makeRequest(uri: "/assets/localhost.pem")

        let response = await bundleResource(request: request, in: .module, pathPrefix: ["assets"])

        #expect(response.status == .ok)
        #expect(response.headers.first(name: "last-modified") != nil)
        #expect(response.headers.first(name: "cache-control") == "public, max-age=0, must-revalidate")
    }

    @Test("returns not found for a missing resource")
    func returnsNotFoundForMissingResource() async {
        let request = makeRequest(uri: "/assets/does-not-exist.txt")

        let response = await bundleResource(request: request, in: .module, pathPrefix: ["assets"])

        #expect(response.status == .notFound)
    }

    @Test("rejects parent directory navigation")
    func rejectsParentDirectoryNavigation() async {
        let request = makeRequest(uri: "/assets/%2e%2e/localhost.pem")

        let response = await bundleResource(request: request, in: .module, pathPrefix: ["assets"])

        #expect(response.status == .notFound)
    }

    @Test("registered route serves resources through the application")
    func registeredRouteServesResources() async throws {
        var app = HTTPApplication()
        app.bundleResources("assets", bundle: .module)

        var context = HTTPContext(request: makeRequest(uri: "/assets/localhost.pem"))
        _ = try await app.handler.routeWithDecision(context: &context)

        #expect(context.response.status == .ok)
        #expect(context.response.body != nil)
    }
}
