//
//  Types.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation
import NIOHTTP1
import NIOCore
@propertyWrapper
public struct HTTPRequestCookieCapture: Sendable {
    public var wrappedValue: [String: String]
    public init(wrappedValue: [String:String], headers: HTTPHeaders) {
        self.wrappedValue = getRequestCookies(headers: headers)
    }
}
public struct HTTPRequest: Sendable {
    public let url: URL
    public let method: HTTPMethod
    public lazy var urlComponents: URLComponents = .init(url: url, resolvingAgainstBaseURL: false) ?? .init(string: "/")!
    public let headers: HTTPHeaders
    public let body: ByteBuffer?
    public let trailers: HTTPHeaders?
    public let cookies: [String: String]
}
public struct HTTPResponse: Sendable {
    public var status: HTTPResponseStatus
    public var headers: HTTPHeaders
    public var body: ByteBuffer?
    public var trailers: HTTPHeaders?
    public init() {
        self.status = .ok
        self.headers = HTTPHeaders()
        self.body = nil
        self.trailers = nil
    }
    public init(status: HTTPResponseStatus = .ok, headers: HTTPHeaders = HTTPHeaders(), body: ByteBuffer? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
        self.trailers = nil
    }
}
func tryGetByteBuffer(data: Data?) -> ByteBuffer? {
    guard let data else {
        return nil
    }
    return ByteBuffer(data: data)
}
public func httpContent(status: HTTPResponseStatus = .ok, type: String, headers: HTTPHeaders = HTTPHeaders(), data: () -> Data?) -> HTTPResponse {
    var response = HTTPResponse(status: status, headers: headers, body: tryGetByteBuffer(data: data()))
    response.headers.replaceOrAdd(name: "content-type", value: type)
    return response
}
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
public func json<T: Encodable>(status: HTTPResponseStatus = .ok, headers: HTTPHeaders = HTTPHeaders(), content: () -> T) -> HTTPResponse {
    return json(content(), status: status, headers: headers)
}
public struct HTTPContext: Sendable {
    public let request: HTTPRequest
    public var response: HTTPResponse = .init()
}
import RegexBuilder
public func getRequestCookies(headers: HTTPHeaders) -> [String:String] {
    guard let requestCookies = headers.first(name: "Cookie") else {
        return [:]
    }
    let regex = Regex {
        Capture {
            OneOrMore {
                CharacterClass(
                    .word,
                    .anyOf("-_")
                )
            }
        }
        "="
        Capture {
            ZeroOrMore {
                NegativeLookahead {
                    ";"
                }
                CharacterClass.any
            }
        }
    }
    var cookies: [String:String] = [:]
    for match in requestCookies.matches(of: regex) {
        cookies[match.output.1.description] = match.output.2.description
    }
    return cookies
}
