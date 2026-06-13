//
//  StaticFiles.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-06-13.
//

import Foundation
import NIOHTTP1
import NIOPosix

/// Serves a filesystem file mapped from the request path.
///
/// The requested path is resolved relative to `location` after removing `pathPrefix`.
/// Unsafe path components, encoded slashes, directory traversal, directories, and
/// symlink escapes outside `location` are rejected with `404 Not Found`. File metadata
/// and content are read off the NIO event loop.
///
/// - Parameters:
///   - request: The incoming request whose URL path selects the file.
///   - location: The root directory to serve from.
///   - pathPrefix: URL path segments to strip before resolving the file path.
///   - mimeTypes: Registry used to choose the response `Content-Type`.
///   - defaultMimeType: Content type used for unknown extensions.
///   - cacheControl: Optional `Cache-Control` header value.
public func staticFile(
    request: HTTPRequest,
    from location: URL,
    pathPrefix: [String] = [],
    mimeTypes: HTTPMimeTypeRegistry = .default,
    defaultMimeType: String = "application/octet-stream",
    cacheControl: String? = "public, max-age=0, must-revalidate"
) async -> HTTPResponse {
    guard location.isFileURL,
          let relativeComponents = safeStaticFilePathComponents(for: request, removing: pathPrefix) else {
        return HTTPResponse(status: .notFound)
    }

    let baseURL = location.standardizedFileURL

    // Resolve symlinks and read the file's metadata off the event loop:
    // `resolvingSymlinksInPath()`, `fileExists`, and `attributesOfItem` all issue
    // blocking filesystem syscalls and must never run on a NIO event-loop thread.
    let probe: StaticFileProbe
    do {
        probe = try await NIOThreadPool.singleton.runIfActive {
            probeStaticFile(baseURL: baseURL, relativeComponents: relativeComponents)
        }
    } catch {
        return HTTPResponse(status: .internalServerError)
    }

    let resolvedFileURL: URL
    let lastModified: Date
    switch probe {
    case .notFound:
        return HTTPResponse(status: .notFound)
    case .unreadable:
        return HTTPResponse(status: .internalServerError)
    case let .file(url, modificationDate):
        resolvedFileURL = url
        lastModified = modificationDate
    }

    let validation = HTTPCacheValidation(lastModified: HTTPLastModified(lastModified))
    let cacheHeaders = httpCacheHeaders(validation: validation, cacheControl: cacheControl)
    if isNotModified(request: request, validation: validation) {
        return HTTPResponse(status: .notModified, headers: cacheHeaders)
    }

    // Read the contents off the event loop too. Only reached when the client does
    // not already hold an up-to-date copy (i.e. this is not a 304).
    let data: Data
    do {
        data = try await NIOThreadPool.singleton.runIfActive {
            try Data(contentsOf: resolvedFileURL)
        }
    } catch {
        return HTTPResponse(status: .internalServerError)
    }

    var response = data.http(type: mimeTypes.mimeType(for: resolvedFileURL, default: defaultMimeType))
    response.headers.add(contentsOf: cacheHeaders)
    return response
}

/// Serves a filesystem file mapped from the request path using a string root path.
///
/// This overload converts `location` to a file URL and delegates to the URL-based
/// `staticFile` helper.
///
/// - Parameters:
///   - request: The incoming request whose URL path selects the file.
///   - location: The root directory path to serve from.
///   - pathPrefix: URL path segments to strip before resolving the file path.
///   - mimeTypes: Registry used to choose the response `Content-Type`.
///   - defaultMimeType: Content type used for unknown extensions.
///   - cacheControl: Optional `Cache-Control` header value.
public func staticFile(
    request: HTTPRequest,
    from location: String,
    pathPrefix: [String] = [],
    mimeTypes: HTTPMimeTypeRegistry = .default,
    defaultMimeType: String = "application/octet-stream",
    cacheControl: String? = "public, max-age=0, must-revalidate"
) async -> HTTPResponse {
    await staticFile(
        request: request,
        from: URL(fileURLWithPath: location),
        pathPrefix: pathPrefix,
        mimeTypes: mimeTypes,
        defaultMimeType: defaultMimeType,
        cacheControl: cacheControl
    )
}

/// Outcome of resolving and stat-ing a candidate static file on disk.
private enum StaticFileProbe {
    /// The path does not exist, is a directory, or escapes the served directory.
    case notFound
    /// The file exists but its metadata could not be read (a server-side error).
    case unreadable
    /// The file exists and is readable, with its resolved URL and modification date.
    case file(url: URL, lastModified: Date)
}

/// Resolves `relativeComponents` against `baseURL`, confirms the result stays
/// inside the served directory (after following symlinks), and reads its metadata.
///
/// - Important: Performs blocking filesystem syscalls; invoke off the event loop.
private func probeStaticFile(baseURL: URL, relativeComponents: [String]) -> StaticFileProbe {
    var fileURL = baseURL
    for component in relativeComponents {
        fileURL.appendPathComponent(component, isDirectory: false)
    }

    let resolvedBaseURL = baseURL.resolvingSymlinksInPath()
    let resolvedFileURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
    guard isStaticFileURL(resolvedFileURL, containedIn: resolvedBaseURL) else {
        return .notFound
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolvedFileURL.path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
        return .notFound
    }

    guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedFileURL.path),
          let lastModified = attributes[.modificationDate] as? Date else {
        return .unreadable
    }

    return .file(url: resolvedFileURL, lastModified: lastModified)
}

private func safeStaticFilePathComponents(for request: HTTPRequest, removing pathPrefix: [String]) -> [String]? {
    let percentEncodedPath = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? request.url.path
    let requestComponents = percentEncodedPath
        .split(separator: "/", omittingEmptySubsequences: true)
        .map(String.init)

    var decodedComponents: [String] = []
    decodedComponents.reserveCapacity(requestComponents.count)
    for component in requestComponents {
        guard let decoded = component.removingPercentEncoding,
              isSafeStaticFilePathComponent(decoded) else {
            return nil
        }
        decodedComponents.append(decoded)
    }

    let prefix = routePathSegments(pathPrefix)
    guard decodedComponents.count >= prefix.count else {
        return nil
    }
    for index in prefix.indices {
        guard decodedComponents[index].lowercased() == prefix[index].lowercased() else {
            return nil
        }
    }

    let relativeComponents = Array(decodedComponents.dropFirst(prefix.count))
    return relativeComponents.isEmpty ? nil : relativeComponents
}
private func routePathSegments(_ path: [String]) -> [String] {
    path.flatMap { segment in
        segment.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}

private func isSafeStaticFilePathComponent(_ component: String) -> Bool {
    guard !component.isEmpty, component != ".", component != ".." else {
        return false
    }
    guard !component.contains("/"), !component.contains("\\") else {
        return false
    }
    return component.unicodeScalars.allSatisfy { scalar in
        scalar.value >= 0x20 && scalar.value != 0x7F
    }
}

private func isStaticFileURL(_ fileURL: URL, containedIn baseURL: URL) -> Bool {
    let basePath = baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path
    // Refuse to serve when the base resolves to the filesystem root ("/"): an empty
    // prefix would match every absolute path and defeat the containment check.
    guard !basePath.isEmpty else {
        return false
    }
    let filePath = fileURL.path
    return filePath.hasPrefix(basePath + "/")
}

