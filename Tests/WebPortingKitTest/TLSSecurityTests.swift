import Foundation
import NIOCore
import NIOHTTP1
import Testing
@testable import WebPortingKit

@Suite("TLS security configuration")
struct TLSSecurityTests {
    @Test("plain HTTP uses HTTP/1.1 without TLS")
    func plainHTTPUsesHTTP1WithoutTLS() throws {
        let configuration = try makeHTTPServerChannelConfiguration(identity: .http)

        #expect(configuration.sslContext == nil)
        #expect(configuration.pipelineMode == .http1)
    }

    @Test("HTTPS HTTP/1.1 mode uses TLS with HTTP/1.1")
    func httpsHTTP1ModeUsesTLSWithHTTP1() throws {
        let configuration = try makeHTTPServerChannelConfiguration(
            identity: .secure(try makeFixtureIdentityPair(), mode: .http1)
        )

        #expect(configuration.sslContext != nil)
        #expect(configuration.pipelineMode == .http1)
    }

    @Test("HTTPS HTTP/2 mode uses TLS with HTTP/2")
    func httpsHTTP2ModeUsesTLSWithHTTP2() throws {
        let configuration = try makeHTTPServerChannelConfiguration(
            identity: .secure(try makeFixtureIdentityPair(), mode: .http2)
        )

        #expect(configuration.sslContext != nil)
        #expect(configuration.pipelineMode == .http2)
    }

    @Test("builds SSL context from PEM fixture files")
    func buildsSSLContextFromPEMFixtureFiles() throws {
        let identity = try makeFixtureIdentityPair()

        let sslContext = try makeSSLContext(from: identity)
        #expect(sslContext != nil)
    }

    @Test("builds SSL context for HTTP/1.1 only mode")
    func buildsSSLContextForHTTP1OnlyMode() throws {
        let identity = try makeFixtureIdentityPair()

        let sslContext = try makeSSLContext(from: identity, mode: .http1)
        #expect(sslContext != nil)
    }

    @Test("builds SSL context for negotiated mode")
    func buildsSSLContextForNegotiatedMode() throws {
        let identity = try makeFixtureIdentityPair()

        let sslContext = try makeSSLContext(from: identity, mode: .negotiated)
        #expect(sslContext != nil)
    }

    @Test("HTTPS negotiated mode uses TLS with negotiated pipeline")
    func httpsNegotiatedModeUsesTLSWithNegotiatedPipeline() throws {
        let configuration = try makeHTTPServerChannelConfiguration(
            identity: .secure(try makeFixtureIdentityPair(), mode: .negotiated)
        )

        #expect(configuration.sslContext != nil)
        #expect(configuration.pipelineMode == .negotiated)
    }

    @Test("secure server identity explicitly supports HTTP/1.1 only mode")
    func secureServerIdentityExplicitlySupportsHTTP1OnlyMode() throws {
        let identity = HTTPServerIdentity.secure(
            try makeFixtureIdentityPair(),
            mode: .http1
        )

        guard case .secure(_, let mode) = identity else {
            Issue.record("Expected secure identity")
            return
        }
        #expect(mode == .http1)
    }

    @Test("secure server identity explicitly supports HTTP/2 only mode")
    func secureServerIdentityExplicitlySupportsHTTP2OnlyMode() throws {
        let identity = HTTPServerIdentity.secure(
            try makeFixtureIdentityPair(),
            mode: .http2
        )

        guard case .secure(_, let mode) = identity else {
            Issue.record("Expected secure identity")
            return
        }
        #expect(mode == .http2)
    }

    @Test("secure server identity explicitly supports negotiated mode")
    func secureServerIdentityExplicitlySupportsNegotiatedMode() throws {
        let identity = HTTPServerIdentity.secure(
            try makeFixtureIdentityPair(),
            mode: .negotiated
        )

        guard case .secure(_, let mode) = identity else {
            Issue.record("Expected secure identity")
            return
        }
        #expect(mode == .negotiated)
    }

    @Test("certificate chain loads every PEM block, not just the leaf")
    func certificateChainLoadsEveryPEMBlock() throws {
        let certificateURL = try #require(Bundle.module.url(forResource: "localhost", withExtension: "pem"))
        let singlePEM = try Data(contentsOf: certificateURL)

        // Sanity: a single-certificate PEM yields exactly one chain entry.
        #expect(try certificateChain(from: .data(singlePEM)).count == 1)
        #expect(try certificateChain(from: .file(certificateURL.path)).count == 1)

        // A multi-block PEM (leaf + intermediate, simulated by concatenation) must
        // load every certificate — the previous `.first`/single-cert code dropped all
        // but the leaf, breaking chain delivery.
        var fullChainPEM = singlePEM
        fullChainPEM.append(0x0A)
        fullChainPEM.append(singlePEM)
        #expect(try certificateChain(from: .data(fullChainPEM)).count == 2)
    }

    private func makeFixtureIdentityPair() throws -> SecureIdentityPair {
        let certificateURL = try #require(Bundle.module.url(forResource: "localhost", withExtension: "pem"))
        let privateKeyURL = try #require(Bundle.module.url(forResource: "localhost-key", withExtension: "pem"))

        return SecureIdentityPair.pair(
            privateKey: .url(privateKeyURL),
            certificate: .url(certificateURL)
        )
    }
}
