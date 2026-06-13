import Foundation
import NIOCore
import NIOHTTP1
import Testing
@testable import WebPortingKit

@Suite("HTTP server integration")
struct HTTPServerIntegrationTests {
    @Test("plain HTTP/1.1 server handles a real request")
    func plainHTTP1ServerHandlesRealRequest() async throws {
        let server = TestServer(HTTPServer(identity: .http, app: makeIntegrationApp()))
        let port = try await startServer(server)
        defer {
            Task { await server.value.stop() }
        }

        let response = try await request(url: URL(string: "http://127.0.0.1:\(port)/ping")!)

        #expect(response.statusCode == 200)
        #expect(response.body == "pong")
    }

    @Test("HTTPS HTTP/1.1 server handles a real TLS request")
    func httpsHTTP1ServerHandlesRealTLSRequest() async throws {
        let server = TestServer(
            HTTPServer(
                identity: .secure(try makeFixtureIdentityPair(), mode: .http1),
                app: makeIntegrationApp()
            )
        )
        let port = try await startServer(server)
        defer {
            Task { await server.value.stop() }
        }

        let response = try await request(
            url: URL(string: "https://127.0.0.1:\(port)/ping")!,
            acceptsSelfSignedCertificates: true
        )

        #expect(response.statusCode == 200)
        #expect(response.body == "pong")
    }

    @Test("HTTPS HTTP/2 server handles a real TLS request")
    func httpsHTTP2ServerHandlesRealTLSRequest() async throws {
        let server = TestServer(
            HTTPServer(
                identity: .secure(try makeFixtureIdentityPair(), mode: .http2),
                app: makeIntegrationApp()
            )
        )
        let port = try await startServer(server)
        defer {
            Task { await server.value.stop() }
        }

        let response = try await request(
            url: URL(string: "https://127.0.0.1:\(port)/ping")!,
            acceptsSelfSignedCertificates: true
        )

        #expect(response.statusCode == 200)
        #expect(response.body == "pong")
    }

    @Test("HTTPS negotiated server handles a real TLS request")
    func httpsNegotiatedServerHandlesRealTLSRequest() async throws {
        let server = TestServer(
            HTTPServer(
                identity: .secure(try makeFixtureIdentityPair(), mode: .negotiated),
                app: makeIntegrationApp()
            )
        )
        let port = try await startServer(server)
        defer {
            Task { await server.value.stop() }
        }

        let response = try await request(
            url: URL(string: "https://127.0.0.1:\(port)/ping")!,
            acceptsSelfSignedCertificates: true
        )

        #expect(response.statusCode == 200)
        #expect(response.body == "pong")
    }

    @Test("server can stop and start again")
    func serverCanStopAndStartAgain() async throws {
        let server = TestServer(HTTPServer(identity: .http, app: makeIntegrationApp()))
        let firstRun = try await launchServer(server)
        _ = try await request(url: URL(string: "http://127.0.0.1:\(firstRun.port)/ping")!)

        await server.value.stop()
        try await firstRun.task.value

        let secondRun = try await launchServer(server)
        defer {
            Task { await server.value.stop() }
        }

        let response = try await request(url: URL(string: "http://127.0.0.1:\(secondRun.port)/ping")!)

        #expect(response.statusCode == 200)
        #expect(response.body == "pong")
    }

    private func makeIntegrationApp() -> HTTPApplication<DefaultHTTPRoutingHandler> {
        var app = HTTPApplication()
        app.get("ping") { _ -> HTTPResponse in
            HTTPResponse(
                status: .ok,
                headers: HTTPHeaders([("content-type", "text/plain; charset=utf-8")]),
                body: ByteBufferAllocator().buffer(string: "pong")
            )
        }
        return app
    }

    private func makeFixtureIdentityPair() throws -> SecureIdentityPair {
        let certificateURL = try #require(Bundle.module.url(forResource: "localhost", withExtension: "pem"))
        let privateKeyURL = try #require(Bundle.module.url(forResource: "localhost-key", withExtension: "pem"))

        return SecureIdentityPair.pair(
            privateKey: .url(privateKeyURL),
            certificate: .url(certificateURL)
        )
    }

    private func startServer(
        _ server: TestServer,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Int {
        try await launchServer(server, sourceLocation: sourceLocation).port
    }

    private func launchServer(
        _ server: TestServer,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> (task: Task<Void, any Error>, port: Int) {
        let serverTask = Task {
            try await server.value.start(host: "127.0.0.1", port: 0)
        }

        for _ in 0..<100 {
            if let port = server.value.channel?.localAddress?.port {
                return (serverTask, port)
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        serverTask.cancel()
        Issue.record("Expected server to bind to an ephemeral port", sourceLocation: sourceLocation)
        throw IntegrationTestError.serverDidNotStart
    }

    private func request(
        url: URL,
        acceptsSelfSignedCertificates: Bool = false
    ) async throws -> (statusCode: Int, body: String) {
        let session: URLSession
        if acceptsSelfSignedCertificates {
            session = URLSession(
                configuration: .ephemeral,
                delegate: SelfSignedCertificateDelegate(),
                delegateQueue: nil
            )
        } else {
            session = URLSession(configuration: .ephemeral)
        }
        defer {
            session.invalidateAndCancel()
        }

        let (data, response) = try await session.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)
        return (
            statusCode: httpResponse.statusCode,
            body: String(decoding: data, as: UTF8.self)
        )
    }
}

enum IntegrationTestError: Error {
    case serverDidNotStart
}

final class TestServer: @unchecked Sendable {
    let value: HTTPServer<DefaultHTTPRoutingHandler>

    init(_ value: HTTPServer<DefaultHTTPRoutingHandler>) {
        self.value = value
    }
}

final class SelfSignedCertificateDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
