//
//  CacheControl.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-06-13.
//

import Foundation
import NIOHTTP1

/// Cache validators that can be attached to a response and checked against a request.
public struct HTTPCacheValidation: Sendable, Hashable {
    /// The `Last-Modified` validator for the resource, if available.
    public var lastModified: HTTPLastModified?

    /// The `ETag` validator for the resource, if available.
    public var eTag: HTTPETag?

    /// Creates cache validation metadata.
    ///
    /// - Parameters:
    ///   - lastModified: The resource's last-modified validator.
    ///   - eTag: The resource's entity tag validator.
    public init(lastModified: HTTPLastModified? = nil, eTag: HTTPETag? = nil) {
        self.lastModified = lastModified
        self.eTag = eTag
    }
}

extension HTTPHeaders {
    /// Adds a `Cache-Control` header.
    ///
    /// - Parameter cacheControl: The header value to add.
    public mutating func add(cacheControl: String) {
        self.add(name: "cache-control", value: cacheControl)
    }

    /// Adds cache validation headers and an optional `Cache-Control` header.
    ///
    /// - Parameters:
    ///   - cacheValidation: The validators to serialize.
    ///   - cacheControl: An optional `Cache-Control` header value.
    public mutating func add(cacheValidation: HTTPCacheValidation, cacheControl: String? = nil) {
        if let lastModified = cacheValidation.lastModified {
            self.add(lastModified: lastModified)
        }
        if let eTag = cacheValidation.eTag {
            self.add(eTag: eTag)
        }
        if let cacheControl {
            self.add(cacheControl: cacheControl)
        }
    }
}

/// Builds headers containing the supplied cache validators and optional cache policy.
///
/// - Parameters:
///   - validation: The validators to serialize.
///   - cacheControl: An optional `Cache-Control` header value.
public func httpCacheHeaders(validation: HTTPCacheValidation, cacheControl: String? = nil) -> HTTPHeaders {
    var headers = HTTPHeaders()
    headers.add(cacheValidation: validation, cacheControl: cacheControl)
    return headers
}

/// Returns whether `request` can be answered with `304 Not Modified`.
///
/// `If-None-Match` takes precedence over `If-Modified-Since`, matching HTTP cache
/// validation rules.
///
/// - Parameters:
///   - request: The incoming request containing optional conditional headers.
///   - validation: The current validators for the resource.
public func isNotModified(request: HTTPRequest, validation: HTTPCacheValidation) -> Bool {
    if let ifNoneMatch = request.headers.ifNoneMatch {
        guard let eTag = validation.eTag else {
            return false
        }
        return request.headers.matches(ifNoneMatch: ifNoneMatch, currentETag: eTag)
    }

    guard let lastModified = validation.lastModified else {
        return false
    }
    return isNotModified(request: request, lastModified: lastModified.date)
}
