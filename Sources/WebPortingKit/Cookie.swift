//
//  Cookie.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation
import NIOHTTP1
public enum SameSite: String {
    case lax = "Lax"
    case strict = "Strict"
    case none = "None"
}
public enum CookieOption {
    case domain(String)
    case expires(Date)
    case httpOnly
    case maxAge(TimeInterval)
    case path(String)
    case secure
    case sameSite(SameSite)
    case partioned
}
public struct ResponseCookie {
    public let name: String
    public let value: String
    public let options: [CookieOption]
    public init(name: String, value: String, options: CookieOption...) {
        self.name = name
        self.value = value
        self.options = options
    }
    public init(name: String, value: String, options: [CookieOption]) {
        self.name = name
        self.value = value
        self.options = options
    }
}
extension CookieOption {
    public var appendString: String {
        return switch self {
        case .domain(let value):
            "; Domain=\(value)"
        case .expires(let value):
            "; Expires=\(value.headerDateFormat)"
        case .httpOnly:
            "; HttpOnly"
        case .maxAge(let value):
            "; Max-Age=\(Int(value))"
        case .path(let value):
            "; Path=\(value)"
        case .secure:
            "; Secure"
        case .sameSite(let value):
            "; SameSite=\(value.rawValue)"
        case .partioned:
            "; Partitioned"
        }
    }
}
extension Array<CookieOption> {
    public var string: String {
        self.map { $0.appendString }.joined()
    }
}
extension HTTPHeaders {
    public mutating func add(cookie: ResponseCookie) {
        self.add(name: "Set-Cookie", value: "\(cookie.name)=\(cookie.value)\(cookie.options.string)")
    }
}
extension Date {
    var headerDateFormat: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let string = formatter.string(from: self)
        return string
    }
}
