//
//  Security.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import NIOSSL
import Foundation

/// A PEM-encoded TLS identity source.
public enum SecureServerIdentity: Sendable {
    /// Load PEM data from a filesystem path.
    case file(String)

    /// Load PEM data from a file URL.
    case url(URL)

    /// Load PEM data from memory.
    case data(Data)
}

/// The private key and certificate chain used by a secure HTTP server.
public enum SecureIdentityPair: Sendable {
    /// A private key and certificate chain pair.
    case pair(privateKey: SecureServerIdentity, certificate: SecureServerIdentity)
}

func makeSSLContext(from pair: SecureIdentityPair, mode: HTTPSProtocolMode = .http2) throws -> NIOSSLContext? {
    guard case .pair(let privateKey, let certificate) = pair else {
        return nil
    }
    var sslPrivateKey: NIOSSLPrivateKeySource
    switch privateKey {
    case .file(let file):
        sslPrivateKey = try .privateKey(NIOSSLPrivateKey.init(file: file, format: .pem))
    case .data(let data):
        sslPrivateKey = try .privateKey(NIOSSLPrivateKey.init(bytes: [UInt8](data), format: .pem))
    case .url(let url):
        let data = try Data(contentsOf: url)
        sslPrivateKey = try .privateKey(NIOSSLPrivateKey.init(bytes: [UInt8](data), format: .pem))
    }
    let sslCertificateChain = try certificateChain(from: certificate)
    guard !sslCertificateChain.isEmpty else {
        return nil
    }
    var serverConfig = TLSConfiguration.makeServerConfiguration(
        certificateChain: sslCertificateChain,
        privateKey: sslPrivateKey
    )
    switch mode {
    case .http1:
        serverConfig.applicationProtocols = ["http/1.1"]
    case .http2:
        serverConfig.applicationProtocols = ["h2"]
    case .negotiated:
        serverConfig.applicationProtocols = ["h2", "http/1.1"]
    }
    // Configure the SSL context that is used by all SSL handlers.
    return try NIOSSLContext(configuration: serverConfig)
}

/// Loads the full certificate chain (leaf followed by any intermediates) from a
/// PEM source, preserving file order.
///
/// - Important: PEM blocks must be ordered leaf-first, then intermediates ascending
///   toward, but not including, the root, as in a typical `fullchain.pem`.
func certificateChain(from source: SecureServerIdentity) throws -> [NIOSSLCertificateSource] {
    let certificates: [NIOSSLCertificate]
    switch source {
    case .file(let file):
        certificates = try NIOSSLCertificate.fromPEMFile(file)
    case .data(let data):
        certificates = try NIOSSLCertificate.fromPEMBytes([UInt8](data))
    case .url(let url):
        certificates = try NIOSSLCertificate.fromPEMBytes([UInt8](Data(contentsOf: url)))
    }
    return certificates.map { NIOSSLCertificateSource.certificate($0) }
}
