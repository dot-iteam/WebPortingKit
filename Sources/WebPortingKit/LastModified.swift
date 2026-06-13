//
//  LastModified.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-06-13.
//

import Foundation
import NIOHTTP1

/// A `Last-Modified` header value rounded to HTTP-date precision.
///
/// HTTP dates do not carry fractional seconds. The stored date is rounded down to
/// whole seconds so comparison and serialization match the value sent on the wire.
public struct HTTPLastModified: Sendable, Hashable {
    /// The modification date rounded down to whole seconds.
    public let date: Date

    /// Creates a last-modified value from `date`.
    ///
    /// - Parameter date: The resource modification date.
    public init(_ date: Date) {
        self.date = date.roundedDownToHTTPDate
    }

    /// The RFC 1123 HTTP-date string used in a `Last-Modified` header.
    public var headerValue: String {
        httpDateString(from: date)
    }
}

extension HTTPHeaders {
    /// Adds a `Last-Modified` header.
    ///
    /// - Parameter lastModified: The value to serialize into the header.
    public mutating func add(lastModified: HTTPLastModified) {
        self.add(name: "last-modified", value: lastModified.headerValue)
    }

    /// The parsed `If-Modified-Since` request header, if present and valid.
    public var ifModifiedSince: Date? {
        guard let value = self.first(name: "if-modified-since") else {
            return nil
        }
        return httpDate(from: value)
    }
}

/// Returns whether `request` can be answered with `304 Not Modified` for `lastModified`.
///
/// - Parameters:
///   - request: The incoming request containing optional conditional headers.
///   - lastModified: The current resource modification date.
public func isNotModified(request: HTTPRequest, lastModified: Date) -> Bool {
    guard let requestedDate = request.headers.ifModifiedSince else {
        return false
    }

    return lastModified.roundedDownToHTTPDate <= requestedDate
}

/// Formats `date` as an RFC 1123 HTTP-date string in GMT.
///
/// Fractional seconds are rounded down before formatting.
public func httpDateString(from date: Date) -> String {
    HTTPDateFormatter.string(from: date.roundedDownToHTTPDate)
}

/// Parses an RFC 1123 HTTP-date string.
///
/// - Parameter value: A date string such as `Tue, 14 Nov 2023 22:13:20 GMT`.
public func httpDate(from value: String) -> Date? {
    HTTPDateFormatter.date(from: value)
}

private enum HTTPDateFormatter {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()

    static func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.date(from: value)
    }
}

private extension Date {
    var roundedDownToHTTPDate: Date {
        Date(timeIntervalSince1970: floor(self.timeIntervalSince1970))
    }
}
