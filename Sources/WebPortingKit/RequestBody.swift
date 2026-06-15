//
//  RequestBody.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation

private func mediaType(from contentType: String) -> String? {
    contentType
        .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

extension HTTPRequest {
    /// Decodes the request body into `Form`, choosing the decoder from the `Content-Type`.
    ///
    /// - `application/json` → `JSONDecoder`
    /// - `application/x-www-form-urlencoded` → ``FormDataDecoding``
    /// - `multipart/form-data` → ``MultipartFormDecoding`` (so `Form` may include `Data`,
    ///   ``MultipartFile``, `[Data]`, or `[MultipartFile]` properties for file parts)
    ///
    /// For any other content type, `fallback` is invoked with the raw body bytes and the
    /// lowercased media type — or `nil` when the request had no `Content-Type` — letting the
    /// caller decode custom formats.
    ///
    /// - Parameters:
    ///   - type: The expected Swift model type (inferred from context when omitted).
    ///   - fallback: A decoder invoked with `(body, mediaType)` when the built-in decoders do
    ///     not recognize the content type. `mediaType` is `nil` when the request had none.
    /// - Returns: The decoded value, or `nil` when the body is missing, decoding fails, or no
    ///   `fallback` handled an unrecognized content type.
    public func getForm<Form: Decodable>(
        _ type: Form.Type = Form.self,
        fallback: ((_ body: Data, _ mediaType: String?) throws -> Form?)? = nil
    ) -> Form? {
        guard let body else {
            return nil
        }
        let data = Data(buffer: body)
        guard let contentType = headers.first(name: "content-type") else {
            guard let fallback else { return nil }
            return try? fallback(data, nil)
        }
        switch mediaType(from: contentType) {
        case "application/json":
            return try? JSONDecoder().decode(Form.self, from: data)
        case "application/x-www-form-urlencoded":
            return decodeFormURL(Form.self, String(decoding: data, as: UTF8.self))
        case "multipart/form-data":
            guard let stream = MultipartFormStream(data: data, contentType: contentType) else {
                return nil
            }
            return try? MultipartFormDecoding(stream: stream).decode(Form.self)
        case let media:
            guard let fallback else { return nil }
            return try? fallback(data, media)
        }
    }

    /// Decodes the request body into `Form`, choosing the decoder from the `Content-Type`,
    /// and falling back to an *asynchronous* decoder for unrecognized content types.
    ///
    /// Use this overload when mapping the body to `Form` requires asynchronous work — for
    /// example, reading from a database, a configuration store, or another async source. The
    /// built-in JSON, form-url-encoded, and multipart decoders still run synchronously; only
    /// unrecognized content types reach `fallback`.
    ///
    /// - Parameters:
    ///   - type: The expected Swift model type (inferred from context when omitted).
    ///   - fallback: An async decoder invoked with `(body, mediaType)` when the built-in
    ///     decoders do not recognize the content type. `mediaType` is `nil` when the request
    ///     had none.
    /// - Returns: The decoded value, or `nil` when the body is missing, decoding fails, or the
    ///   fallback returns `nil` or throws.
    public func getForm<Form: Decodable>(
        _ type: Form.Type = Form.self,
        fallback: (_ body: Data, _ mediaType: String?) async throws -> Form?
    ) async -> Form? {
        guard let body else {
            return nil
        }
        let data = Data(buffer: body)
        guard let contentType = headers.first(name: "content-type") else {
            return try? await fallback(data, nil)
        }
        switch mediaType(from: contentType) {
        case "application/json":
            return try? JSONDecoder().decode(Form.self, from: data)
        case "application/x-www-form-urlencoded":
            return decodeFormURL(Form.self, String(decoding: data, as: UTF8.self))
        case "multipart/form-data":
            guard let stream = MultipartFormStream(data: data, contentType: contentType) else {
                return nil
            }
            return try? MultipartFormDecoding(stream: stream).decode(Form.self)
        case let media:
            return try? await fallback(data, media)
        }
    }
}
