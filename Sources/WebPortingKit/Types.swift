//
//  Types.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation
import NIOHTTP1
import NIOCore
import RegexBuilder

/// Property wrapper that captures request cookies from HTTP headers.
public struct HTTPRequestCookieCapture: Sendable {
    /// Parsed cookie name/value pairs.
    public var wrappedValue: [String: String]

    /// Creates a cookie capture from request headers.
    ///
    /// The supplied `wrappedValue` is ignored; cookies are parsed from `headers`.
    public init(wrappedValue: [String:String], headers: HTTPHeaders) {
        self.wrappedValue = getRequestCookies(headers: headers)
    }
}

/// A normalized HTTP request passed to middleware and route handlers.
public struct HTTPRequest: Sendable {
    /// Per-request async context storage.
    public let context: RequestContext = RequestContext()

    /// The request URL parsed from the request target.
    public let url: URL

    /// The HTTP method.
    public let method: HTTPMethod

    /// URL components for ``url``.
    public var urlComponents: URLComponents {
        .init(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
    }

    /// Request headers.
    public let headers: HTTPHeaders

    /// Request body bytes, if any.
    public let body: ByteBuffer?

    /// Request trailers, if any.
    public let trailers: HTTPHeaders?

    /// Parsed request cookies.
    public let cookies: [String: String]

    /// URL path components exactly as provided by `URL`.
    public var path: [String] {
        url.pathComponents
    }

    /// Lowercased URL path components for case-insensitive route matching.
    public var normalizedPath: [String] {
        url.pathComponents.map { $0.lowercased() }
    }
}

extension Array<String> {
    /// Lowercased path components for route matching.
    public var normalizedPath: [String] {
        self.map { $0.lowercased() }
    }
}

/// An HTTP response produced by middleware or a route handler.
public struct HTTPResponse: Sendable {
    /// Response status code.
    public var status: HTTPResponseStatus

    /// Response headers.
    public var headers: HTTPHeaders

    /// Response body bytes, if any.
    public var body: ByteBuffer?

    /// Response trailers, if any.
    public var trailers: HTTPHeaders?

    /// Creates an empty `200 OK` response.
    public init() {
        self.status = .ok
        self.headers = HTTPHeaders()
        self.body = nil
        self.trailers = nil
    }

    /// Creates a response with status, headers, and optional body.
    public init(status: HTTPResponseStatus = .ok, headers: HTTPHeaders = HTTPHeaders(), body: ByteBuffer? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
        self.trailers = nil
    }

    /// Creates a redirect response and sets the `Location` header.
    ///
    /// - Parameters:
    ///   - location: The redirect target.
    ///   - status: The redirect status. Defaults to `302 Found`.
    ///   - headers: Additional response headers.
    public init(redirect location: String, status: HTTPResponseStatus = .found, headers: HTTPHeaders = HTTPHeaders()) {
        self.init(status: status, headers: headers)
        self.headers.replaceOrAdd(name: "location", value: location)
    }

    /// Creates a redirect response and sets the `Location` header from `URL`.
    public init(redirect location: URL, status: HTTPResponseStatus = .found, headers: HTTPHeaders = HTTPHeaders()) {
        self.init(redirect: location.absoluteString, status: status, headers: headers)
    }

    /// Updates this response to a redirect and replaces the `Location` header.
    public mutating func redirect(to location: String, status: HTTPResponseStatus = .found) {
        self.status = status
        self.headers.replaceOrAdd(name: "location", value: location)
    }

    /// Updates this response to a redirect and replaces the `Location` header from `URL`.
    public mutating func redirect(to location: URL, status: HTTPResponseStatus = .found) {
        redirect(to: location.absoluteString, status: status)
    }
}

extension HTTPHeaders {
    /// Adds a `Location` header.
    public mutating func add(location: String) {
        self.add(name: "location", value: location)
    }

    /// Adds a `Location` header from `URL.absoluteString`.
    public mutating func add(location: URL) {
        self.add(location: location.absoluteString)
    }
}

func tryGetByteBuffer(data: Data?) -> ByteBuffer? {
    guard let data else {
        return nil
    }
    return ByteBuffer(data: data)
}

/// Creates a response from optional data and sets its `Content-Type`.
///
/// - Parameters:
///   - status: Response status. Defaults to `200 OK`.
///   - type: The response `Content-Type` value.
///   - headers: Initial response headers.
///   - data: Closure that returns response body data.
public func httpContent(status: HTTPResponseStatus = .ok, type: String, headers: HTTPHeaders = HTTPHeaders(), data: () -> Data?) -> HTTPResponse {
    var response = HTTPResponse(status: status, headers: headers, body: tryGetByteBuffer(data: data()))
    response.headers.replaceOrAdd(name: "content-type", value: type)
    return response
}

/// Encodes `value` as JSON and returns an HTTP response.
///
/// If encoding fails, the response body is `nil` but the JSON content type is still set.
public func json<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponse {
    let encoder = JSONEncoder()
    let encoded = try? encoder.encode(value)
    var response = HTTPResponse(
        status: status,
        headers: headers,
        body: tryGetByteBuffer(data: encoded)
    )
    response.headers.replaceOrAdd(name: "content-type", value: "application/json; charset=utf-8")
    return response
}

/// Encodes the result of `content` as JSON and returns an HTTP response.
public func json<T: Encodable>(status: HTTPResponseStatus = .ok, headers: HTTPHeaders = HTTPHeaders(), content: () -> T) -> HTTPResponse {
    return json(content(), status: status, headers: headers)
}

/// Mutable request/response state passed through middleware and routes.
public struct HTTPContext: Sendable {
    /// The incoming request.
    public let request: HTTPRequest

    /// The response being built for the request.
    public var response: HTTPResponse = .init()
}

/// Parses all `Cookie` headers into a dictionary of cookie name/value pairs.
///
/// Invalid cookie pairs are ignored. Later cookies with the same name replace earlier
/// values.
public func getRequestCookies(headers: HTTPHeaders) -> [String:String] {
    let regex = Regex {
        Anchor.startOfSubject
        ZeroOrMore { CharacterClass.whitespace }
        Capture {
            OneOrMore {
                CharacterClass(
                    .word,
                    .anyOf("!#$%&'*+-.^`|~")
                )
            }
        }
        ZeroOrMore { CharacterClass.whitespace }
        "="
        ZeroOrMore { CharacterClass.whitespace }
        Capture {
            ZeroOrMore {
                CharacterClass.any
            }
        }
        Anchor.endOfSubject
    }
    var cookies: [String:String] = [:]
    for requestCookies in headers["Cookie"] {
        for part in requestCookies.split(separator: ";", omittingEmptySubsequences: false) {
            guard let match = String(part).firstMatch(of: regex) else {
                continue
            }
            let name = match.output.1.description
            guard isValidCookieName(name) else {
                continue
            }
            var value = match.output.2.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               value.first == "\"",
               value.last == "\"" {
                value.removeFirst()
                value.removeLast()
            }
            cookies[name] = value
        }
    }
    return cookies
}
