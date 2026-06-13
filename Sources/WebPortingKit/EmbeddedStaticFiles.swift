//
//  EmbeddedStaticFiles.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-06-13.
//

import Foundation
import NIOHTTP1

/// An in-memory or generated HTTP resource identified by a stable ID.
public struct EmbeddedHTTPResource<ID: Hashable & Sendable>: Sendable {
    /// Stable identity used for last-modified and generated-ETag metadata caches.
    public let id: ID

    /// Closure that returns the resource bytes.
    public let data: @Sendable () -> Data

    /// The response `Content-Type` for the resource.
    public let mimeType: String

    /// Optional ETag source for cache validation.
    public let eTag: HTTPETagSource?

    /// Creates an embedded resource with a data-producing closure.
    ///
    /// - Parameters:
    ///   - id: Stable identity used for resource metadata.
    ///   - mimeType: Response content type.
    ///   - eTag: Optional ETag source.
    ///   - data: Closure that returns the resource bytes.
    public init(
        id: ID,
        mimeType: String,
        eTag: HTTPETagSource? = nil,
        data: @escaping @Sendable () -> Data
    ) {
        self.id = id
        self.mimeType = mimeType
        self.eTag = eTag
        self.data = data
    }

    /// Creates an embedded resource from a byte array.
    ///
    /// - Parameters:
    ///   - id: Stable identity used for resource metadata.
    ///   - mimeType: Response content type.
    ///   - eTag: Optional ETag source.
    ///   - bytes: Resource bytes copied into `Data` when served.
    public init(
        id: ID,
        mimeType: String,
        eTag: HTTPETagSource? = nil,
        bytes: [UInt8]
    ) {
        self.init(id: id, mimeType: mimeType, eTag: eTag) {
            Data(bytes)
        }
    }
}

/// Actor-backed metadata cache for embedded resources.
///
/// The store assigns stable last-modified dates per resource ID and optionally caches
/// generated ETags by resource ID and generator name.
public actor EmbeddedResourceMetadataStore {
    /// Shared metadata store for embedded resource helpers.
    public static let shared = EmbeddedResourceMetadataStore()

    private var lastModifiedDates: [AnyHashable: Date] = [:]
    private var generatedETags: [EmbeddedResourceGeneratedETagCacheKey: HTTPETag] = [:]

    /// Creates an empty metadata store.
    public init() {}

    /// Returns metadata for an embedded resource.
    ///
    /// - Parameters:
    ///   - resourceID: Stable resource identity.
    ///   - data: Closure used when a generated ETag needs resource bytes.
    ///   - eTag: Optional ETag source.
    public func metadata<ID: Hashable & Sendable>(
        for resourceID: ID,
        data: @Sendable () -> Data,
        eTag: HTTPETagSource?
    ) -> EmbeddedResourceMetadata {
        let resourceKey = AnyHashable(resourceID)
        let lastModified = lastModifiedDate(for: resourceKey)

        guard let eTag else {
            return EmbeddedResourceMetadata(lastModified: lastModified, eTag: nil)
        }

        switch eTag {
        case .constant(let value):
            return EmbeddedResourceMetadata(lastModified: lastModified, eTag: value)
        case .generated:
            guard eTag.shouldCacheGeneratedValue else {
                return EmbeddedResourceMetadata(lastModified: lastModified, eTag: eTag.eTag(for: data()))
            }

            guard let cacheIdentity = eTag.cacheIdentity else {
                return EmbeddedResourceMetadata(lastModified: lastModified, eTag: eTag.eTag(for: data()))
            }
            let eTagKey = EmbeddedResourceGeneratedETagCacheKey(
                resourceID: resourceKey,
                eTagGenerationName: cacheIdentity
            )
            if let eTag = generatedETags[eTagKey] {
                return EmbeddedResourceMetadata(lastModified: lastModified, eTag: eTag)
            }

            let generatedETag = eTag.eTag(for: data())
            generatedETags[eTagKey] = generatedETag
            return EmbeddedResourceMetadata(lastModified: lastModified, eTag: generatedETag)
        }
    }

    private func lastModifiedDate(for resourceID: AnyHashable) -> Date {
        if let date = lastModifiedDates[resourceID] {
            return date
        }

        let date = Date()
        lastModifiedDates[resourceID] = date
        return date
    }
}

private struct EmbeddedResourceGeneratedETagCacheKey: Hashable {
    let resourceID: AnyHashable
    let eTagGenerationName: String
}

/// Cached metadata for an embedded resource response.
public struct EmbeddedResourceMetadata: Sendable {
    /// Stable last-modified date for the resource ID.
    public let lastModified: Date

    /// Optional ETag for the resource.
    public let eTag: HTTPETag?
}

/// Serves an ``EmbeddedHTTPResource`` as an HTTP response.
///
/// The response includes cache validation headers and returns `304 Not Modified` when
/// request validators are fresh.
///
/// - Parameters:
///   - request: The incoming request.
///   - resource: The embedded resource to serve.
///   - metadataStore: Store used for last-modified and generated-ETag metadata.
///   - cacheControl: Optional `Cache-Control` header value.
public func embeddedResource<ID: Hashable & Sendable>(
    request: HTTPRequest,
    resource: EmbeddedHTTPResource<ID>,
    metadataStore: EmbeddedResourceMetadataStore = .shared,
    cacheControl: String? = "public, max-age=0, must-revalidate"
) async -> HTTPResponse {
    await embeddedResource(
        request: request,
        id: resource.id,
        mimeType: resource.mimeType,
        data: resource.data,
        metadataStore: metadataStore,
        cacheControl: cacheControl,
        eTag: resource.eTag
    )
}

/// Serves embedded bytes as an HTTP response.
///
/// Use this overload when the resource is represented directly by an ID, MIME type,
/// and data closure rather than an ``EmbeddedHTTPResource`` value.
///
/// - Parameters:
///   - request: The incoming request.
///   - id: Stable resource identity.
///   - mimeType: Response content type.
///   - data: Closure that returns resource bytes.
///   - metadataStore: Store used for last-modified and generated-ETag metadata.
///   - cacheControl: Optional `Cache-Control` header value.
///   - eTag: Optional ETag source.
public func embeddedResource<ID: Hashable & Sendable>(
    request: HTTPRequest,
    id: ID,
    mimeType: String,
    data: @escaping @Sendable () -> Data,
    metadataStore: EmbeddedResourceMetadataStore = .shared,
    cacheControl: String? = "public, max-age=0, must-revalidate",
    eTag: HTTPETagSource? = nil
) async -> HTTPResponse {
    let metadata = await metadataStore.metadata(for: id, data: data, eTag: eTag)
    let validation = HTTPCacheValidation(lastModified: HTTPLastModified(metadata.lastModified), eTag: metadata.eTag)
    let cacheHeaders = httpCacheHeaders(validation: validation, cacheControl: cacheControl)

    if isNotModified(request: request, validation: validation) {
        return HTTPResponse(status: .notModified, headers: cacheHeaders)
    }

    var response = data().http(type: mimeType)
    response.headers.add(contentsOf: cacheHeaders)
    return response
}
