//
//  BundleResources.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-06-13.
//

import Foundation
import NIOHTTP1

/// Serves a file packaged as a resource inside `bundle` as an HTTP response.
///
/// Bundle resources are regular files on disk, so this simply roots ``staticFile(request:from:pathPrefix:mimeTypes:defaultMimeType:cacheControl:)``
/// at the bundle's resource directory and inherits its path-traversal protection,
/// off-event-loop I/O, MIME-type detection, and last-modified / 304 caching.
///
/// - Note: Resources served as a directory tree (e.g. `/css/app.css`) should be
///   added to the target with `.copy(...)`, which preserves their on-disk layout.
///   `.process(...)` may flatten or rename resources, breaking nested paths.
///
/// - Parameters:
///   - request: The incoming request whose path is mapped to a resource.
///   - bundle: The bundle to serve resources from. Defaults to `.main` (the app's
///     own bundle), *not* WebPortingKit's bundle.
///   - subdirectory: An optional resource subdirectory to root serving at.
///   - pathPrefix: URL path segments to strip before mapping to a resource.
///   - mimeTypes: The registry used to pick the `Content-Type`.
///   - defaultMimeType: The `Content-Type` used when the extension is unknown.
///   - cacheControl: The `Cache-Control` header value, or `nil` to omit it.
public func bundleResource(
    request: HTTPRequest,
    in bundle: Bundle,
    subdirectory: String? = nil,
    pathPrefix: [String] = [],
    mimeTypes: HTTPMimeTypeRegistry = .default,
    defaultMimeType: String = "application/octet-stream",
    cacheControl: String? = "public, max-age=0, must-revalidate"
) async -> HTTPResponse {
    guard let root = bundleResourceRoot(in: bundle, subdirectory: subdirectory) else {
        return HTTPResponse(status: .notFound)
    }
    return await staticFile(
        request: request,
        from: root,
        pathPrefix: pathPrefix,
        mimeTypes: mimeTypes,
        defaultMimeType: defaultMimeType,
        cacheControl: cacheControl
    )
}

/// Resolves the directory that resources are served from for `bundle`, applying an
/// optional `subdirectory`. Returns `nil` when the bundle has no resource directory.
func bundleResourceRoot(in bundle: Bundle, subdirectory: String?) -> URL? {
    guard var root = bundle.resourceURL else {
        return nil
    }
    if let subdirectory {
        for component in subdirectory.split(separator: "/", omittingEmptySubsequences: true) {
            root.appendPathComponent(String(component), isDirectory: true)
        }
    }
    return root
}

extension DefaultHTTPRoutingHandler {
    /// Registers a prefix `GET` route that serves resources from `bundle`.
    public mutating func bundleResources(
        path: [String],
        bundle: Bundle,
        subdirectory: String? = nil,
        mimeTypes: HTTPMimeTypeRegistry = .default,
        defaultMimeType: String = "application/octet-stream",
        cacheControl: String? = "public, max-age=0, must-revalidate"
    ) {
        // Resolve the resource directory once, at registration time, so the route
        // closure captures a `Sendable` URL rather than the non-`Sendable` `Bundle`.
        let root = bundleResourceRoot(in: bundle, subdirectory: subdirectory)
        self.matchMethod(method: .GET, path: path) { request in
            guard let root else {
                return HTTPResponse(status: .notFound)
            }
            return await staticFile(
                request: request,
                from: root,
                pathPrefix: path,
                mimeTypes: mimeTypes,
                defaultMimeType: defaultMimeType,
                cacheControl: cacheControl
            )
        }
    }
}

extension HTTPApplication where RoutingHandler == DefaultHTTPRoutingHandler {
    /// Registers a prefix `GET` route that serves resources from `bundle`.
    public mutating func bundleResources(
        _ path: String...,
        bundle: Bundle,
        subdirectory: String? = nil,
        mimeTypes: HTTPMimeTypeRegistry = .default,
        defaultMimeType: String = "application/octet-stream",
        cacheControl: String? = "public, max-age=0, must-revalidate"
    ) {
        handler.bundleResources(
            path: path,
            bundle: bundle,
            subdirectory: subdirectory,
            mimeTypes: mimeTypes,
            defaultMimeType: defaultMimeType,
            cacheControl: cacheControl
        )
    }
}
