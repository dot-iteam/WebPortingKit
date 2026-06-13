//
//  RequestBody.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation
import RegexBuilder

/// The decoded representation selected from an HTTP request body.
///
/// `HTTPRequest.getBody(type:)` chooses one case from the request's `Content-Type`:
/// JSON and form-url-encoded bodies become ``object(_:)``, multipart bodies become
/// ``multipartFormStream(_:)``, and unknown or missing content types become raw
/// ``data(_:)``.
public enum RequestBody<Body: Decodable> {
    /// A typed body decoded from JSON or `application/x-www-form-urlencoded` data.
    case object(Body?)

    /// A multipart stream ready to be consumed with ``decodeMultipartFormData(type:stream:)``.
    case multipartFormStream(MultipartFormStream?)

    /// Raw body bytes for unsupported content types, or `nil` when the request had no body.
    case data(Data?)
}

/// Empty decodable placeholder used when only multipart files are needed.
public struct NoDecodableData: Decodable {}

private func mediaType(from contentType: String) -> String {
    contentType
        .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
}

extension HTTPRequest {
    /// Decodes the body according to the request `Content-Type`.
    ///
    /// - Parameter type: The expected Swift model type for JSON or form fields.
    /// - Returns: A ``RequestBody`` case describing the body representation that was available.
    public func getBody<T: Decodable>(type: T.Type) -> RequestBody<T> {
        guard let body = self.body else {
            return .data(nil)
        }
        guard let contentType = self.headers.first(name: "content-type") else {
            return .data(Data(buffer: body))
        }
        switch mediaType(from: contentType) {
        case "application/json":
            return .object(try? JSONDecoder().decode(T.self, from: Data(buffer: body)))
        case "application/x-www-form-urlencoded":
            return .object(decodeFormURL(T.self, body.getString(at: 0, length: body.readableBytes) ?? ""))
        case "multipart/form-data":
            return .multipartFormStream(MultipartFormStream(data: Data(buffer: body), contentType: contentType))
        default:
            return .data(Data(buffer: body))
        }
    }

    /// Decodes the body and passes the selected body representation to `callback`.
    ///
    /// - Parameters:
    ///   - type: The expected Swift model type for JSON or form fields.
    ///   - callback: A synchronous callback receiving the selected ``RequestBody`` case.
    public func getBody<T: Decodable>(type: T.Type, callback: (RequestBody<T>) -> Void) {
        callback(getBody(type: type))
    }

    /// Returns only the typed form or JSON value from the request body.
    ///
    /// Multipart file parts are ignored by this helper. Use ``getDecodedForm(type:)`` when
    /// multipart files must be retained separately from typed fields.
    ///
    /// - Parameter type: The expected Swift model type.
    /// - Returns: The decoded value, or `nil` when decoding fails or the body is raw data.
    public func getDecodedBody<T: Decodable>(type: T.Type) -> T? {
        switch getBody(type: type) {
        case .object(let value):
            return value
        case .multipartFormStream(let stream):
            guard var stream else {
                return nil
            }
            return decodeMultipartFormData(type: type, stream: &stream).form
        default:
            return nil
        }
    }

    /// Decodes URL-encoded or multipart form data into typed fields and separated files.
    ///
    /// For `application/x-www-form-urlencoded`, ``DecodedMultipartForm/files`` is empty.
    /// For `multipart/form-data`, non-file fields are decoded into ``DecodedMultipartForm/form``
    /// and file-like parts are returned in ``DecodedMultipartForm/files``.
    ///
    /// - Parameter type: The expected Swift model type for non-file form fields.
    /// - Returns: The decoded form wrapper. Missing or undecodable forms produce `form == nil`.
    public func getDecodedForm<T: Decodable>(type: T.Type) -> DecodedMultipartForm<T> {
        switch getBody(type: type) {
        case .object(let value):
            return DecodedMultipartForm(files: [:], form: value)
        case .multipartFormStream(let stream):
            guard var stream else {
                return DecodedMultipartForm(files: [:], form: nil)
            }
            return decodeMultipartFormData(type: type, stream: &stream)
        default:
            return DecodedMultipartForm(files: [:], form: nil)
        }
    }
}
