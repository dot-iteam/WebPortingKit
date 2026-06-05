//
//  Security.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import NIOSSL
import Foundation
public enum SecureServerIdentity: Sendable {
    case file(String)
    case url(URL)
    case data(Data)
}
public enum SecureIdentityPair: Sendable {
    case pair(privateKey: SecureServerIdentity, certificate: SecureServerIdentity)
}
func makeSSLContext(from pair: SecureIdentityPair) throws -> NIOSSLContext? {
    guard case .pair(let privateKey, let certificate) = pair else {
        return nil
    }
    var sslPrivateKey: NIOSSLPrivateKeySource
    var sslCertificate: NIOSSLCertificateSource
    switch privateKey {
    case .file(let file):
        sslPrivateKey = try .privateKey(NIOSSLPrivateKey.init(file: file, format: .pem))
    case .data(let data):
        sslPrivateKey = try .privateKey(NIOSSLPrivateKey.init(bytes: [UInt8](data), format: .pem))
    case .url(let url):
        let data = try Data(contentsOf: url)
        sslPrivateKey = try .privateKey(NIOSSLPrivateKey.init(bytes: [UInt8](data), format: .pem))
    }
    switch certificate {
    case .file(let file):
        guard let firstCertificate = try NIOSSLCertificate.fromPEMFile(file).first else {
            return nil
        }
        sslCertificate = .certificate(firstCertificate)
    case .data(let data):
        sslCertificate = try .certificate(NIOSSLCertificate.init(bytes: [UInt8](data), format: .pem))
    case .url(let url):
        let data = try Data(contentsOf: url)
        sslCertificate = try .certificate(NIOSSLCertificate.init(bytes: [UInt8](data), format: .pem))
    }
    // Set up the TLS configuration, it's important to set the `applicationProtocols` to
    // `NIOHTTP2SupportedALPNProtocols` which (using ALPN (https://en.wikipedia.org/wiki/Application-Layer_Protocol_Negotiation))
    // advertises the support of HTTP/2 to the client.
    var serverConfig = TLSConfiguration.makeServerConfiguration(
        certificateChain: [sslCertificate],
        privateKey: sslPrivateKey
    )
    serverConfig.applicationProtocols = ["h2"]
    // Configure the SSL context that is used by all SSL handlers.
    let sslContext = try! NIOSSLContext(configuration: serverConfig)
    return sslContext
}
