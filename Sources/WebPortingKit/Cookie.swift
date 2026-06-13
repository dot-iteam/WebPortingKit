//
//  Cookie.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation
import NIOHTTP1

/// Values for the `SameSite` cookie attribute.
public enum SameSite: String {
    /// Send the cookie for same-site requests and top-level cross-site navigations.
    case lax = "Lax"

    /// Send the cookie only for same-site requests.
    case strict = "Strict"

    /// Send the cookie for same-site and cross-site requests.
    case none = "None"
}

/// Attributes that can be appended to a `Set-Cookie` header.
public enum CookieOption {
    /// The `Domain` attribute.
    case domain(String)

    /// The `Expires` attribute, serialized as an HTTP date.
    case expires(Date)

    /// The `HttpOnly` attribute.
    case httpOnly

    /// The `Max-Age` attribute. Negative values are serialized as `0`.
    case maxAge(TimeInterval)

    /// The `Path` attribute.
    case path(String)

    /// The `Secure` attribute.
    case secure

    /// The `SameSite` attribute.
    case sameSite(SameSite)

    /// The `Partitioned` attribute.
    case partitioned
}

/// A response cookie that can be serialized into a `Set-Cookie` header.
public struct ResponseCookie {
    /// The cookie name.
    public let name: String

    /// The cookie value.
    public let value: String

    /// The attributes appended to the cookie.
    public let options: [CookieOption]

    /// Creates a response cookie with variadic options.
    public init(name: String, value: String, options: CookieOption...) {
        self.name = name
        self.value = value
        self.options = options
    }

    /// Creates a response cookie with an explicit options array.
    public init(name: String, value: String, options: [CookieOption]) {
        self.name = name
        self.value = value
        self.options = options
    }
}

extension CookieOption {
    /// The serialized cookie attribute string, or an empty string if invalid.
    public var appendString: String {
        serializedCookieOption(self) ?? ""
    }
}

extension Array<CookieOption> {
    /// The serialized cookie attributes in array order.
    ///
    /// Returns `nil` if any attribute value is invalid for a `Set-Cookie` header.
    public var appendString: String? {
        var serialized = ""
        for option in self {
            guard let option = serializedCookieOption(option) else {
                return nil
            }
            serialized += option
        }
        return serialized
    }
}

extension ResponseCookie {
    var headerValue: String? {
        guard isValidCookieName(name), isValidCookieValue(value) else {
            return nil
        }
        guard let options = self.options.appendString else {
            return nil
        }
        return "\(name)=\(value)\(options)"
    }
}

extension HTTPHeaders {
    /// Adds a `Set-Cookie` header when `cookie` is valid.
    ///
    /// Invalid names, values, or attributes are ignored to avoid producing malformed
    /// or header-injecting output.
    public mutating func add(cookie: ResponseCookie) {
        guard let headerValue = cookie.headerValue else {
            return
        }
        self.add(name: "Set-Cookie", value: headerValue)
    }
}

/// Returns whether `name` is valid for an HTTP cookie.
public func isValidCookieName(_ name: String) -> Bool {
    guard !name.isEmpty else {
        return false
    }
    return name.utf8.allSatisfy(isHTTPTokenByte)
}

/// Returns whether `byte` is allowed in an HTTP token.
public func isHTTPTokenByte(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x21, 0x23...0x27, 0x2A, 0x2B, 0x2D, 0x2E, 0x30...0x39, 0x41...0x5A, 0x5E...0x7A, 0x7C, 0x7E:
        return true
    default:
        return false
    }
}

/// Returns whether `value` is valid for an unquoted cookie value.
public func isValidCookieValue(_ value: String) -> Bool {
    value.utf8.allSatisfy(isCookieValueByte)
}

/// Returns whether `byte` is allowed in an unquoted cookie value.
public func isCookieValueByte(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x21, 0x23...0x2B, 0x2D...0x3A, 0x3C...0x5B, 0x5D...0x7E:
        return true
    default:
        return false
    }
}

private func serializedCookieOption(_ option: CookieOption) -> String? {
    switch option {
    case .domain(let value):
        guard isValidCookieAttributeValue(value) else {
            return nil
        }
        return "; Domain=\(value)"
    case .expires(let value):
        return "; Expires=\(httpDateString(from: value))"
    case .httpOnly:
        return "; HttpOnly"
    case .maxAge(let value):
        return "; Max-Age=\(max(0, Int(value)))"
    case .path(let value):
        guard isValidCookieAttributeValue(value) else {
            return nil
        }
        return "; Path=\(value)"
    case .secure:
        return "; Secure"
    case .sameSite(let value):
        return "; SameSite=\(value.rawValue)"
    case .partitioned:
        return "; Partitioned"
    }
}

private func isValidCookieAttributeValue(_ value: String) -> Bool {
    value.utf8.allSatisfy { byte in
        byte >= 0x20 && byte != 0x7F && byte != 0x3B
    }
}
