//
//  ETag.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-06-13.
//

import Foundation
import NIOHTTP1

/// An HTTP entity tag value.
///
/// The value is stored exactly as it should appear in an `ETag` header, including
/// quotes or a weak validator prefix when those are desired.
public struct HTTPETag: RawRepresentable, Hashable, Sendable {
    /// The serialized entity tag value.
    public let rawValue: String

    /// Creates an entity tag from a raw header value.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates an entity tag from a raw header value.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A named ETag generator for embedded resources.
///
/// The generator name is used as part of the cache key when generated ETags are
/// cached by ``EmbeddedResourceMetadataStore``.
public struct HTTPETagGeneration: Sendable {
    /// The stable identity of this generator.
    public let name: String

    /// Whether generated values should be cached per resource.
    public let cache: Bool

    private let generateETag: @Sendable (Data) -> HTTPETag

    /// Creates a named ETag generator.
    ///
    /// - Parameters:
    ///   - name: A non-empty stable generator name.
    ///   - cache: Whether generated values should be cached per resource.
    ///   - generateETag: Closure that computes an ETag from resource data.
    public init(name: String, cache: Bool = true, generateETag: @escaping @Sendable (Data) -> HTTPETag) {
        precondition(!name.isEmpty, "HTTP ETag generation name must not be empty")
        self.name = name
        self.cache = cache
        self.generateETag = generateETag
    }

    /// Computes an ETag for `data`.
    public func eTag(for data: Data) -> HTTPETag {
        generateETag(data)
    }
}

/// Describes where an ETag for a resource should come from.
public enum HTTPETagSource: Sendable {
    /// A fixed ETag value that does not require reading resource data.
    case constant(HTTPETag)

    /// An ETag generated from resource data.
    case generated(HTTPETagGeneration)

    /// Creates a constant ETag source from a raw header value.
    public static func constant(_ value: String) -> HTTPETagSource {
        .constant(HTTPETag(value))
    }

    /// Creates a generated ETag source that returns raw string values.
    ///
    /// - Parameters:
    ///   - name: A non-empty stable generator name.
    ///   - cache: Whether generated values should be cached per resource.
    ///   - generateETag: Closure that computes a raw ETag string from resource data.
    public static func generated(
        name: String,
        cache: Bool = true,
        generateETag: @escaping @Sendable (Data) -> String
    ) -> HTTPETagSource {
        .generated(
            HTTPETagGeneration(name: name, cache: cache) { data in
                HTTPETag(generateETag(data))
            }
        )
    }

    /// The cache identity used for generated ETags, or `nil` for constant ETags.
    public var cacheIdentity: String? {
        switch self {
        case .constant:
            nil
        case .generated(let generation):
            generation.name
        }
    }

    /// Whether generated ETags should be cached per resource.
    public var shouldCacheGeneratedValue: Bool {
        switch self {
        case .constant:
            false
        case .generated(let generation):
            generation.cache
        }
    }

    /// Returns the ETag for `data`.
    public func eTag(for data: Data) -> HTTPETag {
        switch self {
        case .constant(let eTag):
            eTag
        case .generated(let generation):
            generation.eTag(for: data)
        }
    }
}

extension HTTPHeaders {
    /// Adds an `ETag` header.
    public mutating func add(eTag: HTTPETag) {
        self.add(name: "etag", value: eTag.rawValue)
    }

    /// The raw `If-None-Match` request header value, if present.
    public var ifNoneMatch: String? {
        self.first(name: "if-none-match")
    }

    /// Returns whether an `If-None-Match` header matches `currentETag`.
    ///
    /// Multiple candidates are comma-separated. A candidate of `*` matches any
    /// current ETag. Weak prefixes are ignored for this comparison.
    ///
    /// - Parameters:
    ///   - value: The raw `If-None-Match` header value.
    ///   - currentETag: The resource's current ETag.
    public func matches(ifNoneMatch value: String, currentETag: HTTPETag) -> Bool {
        value.split(separator: ",").contains { candidate in
            let tag = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return tag == "*" || normalizedHTTPETag(tag) == normalizedHTTPETag(currentETag.rawValue)
        }
    }
}

private func normalizedHTTPETag(_ value: String) -> String {
    value.hasPrefix("W/") ? String(value.dropFirst(2)) : value
}
