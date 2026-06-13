//
//  HTTPMimeTypeRegistry.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-06-13.
//

import Foundation

/// A registry that maps file extensions to HTTP `Content-Type` values.
///
/// Extensions are normalized by removing leading/trailing dots and lowercasing, so
/// `"HTML"`, `".html"`, and `"html"` address the same entry.
public struct HTTPMimeTypeRegistry: Sendable, Equatable {
    private var mimeTypes: [String: String]

    /// Creates a registry from an extension-to-MIME dictionary.
    public init(_ mimeTypes: [String: String] = [:]) {
        self.mimeTypes = mimeTypes.reduce(into: [:]) { result, entry in
            result[Self.normalizedExtension(entry.key)] = entry.value
        }
    }

    /// Reads or writes a MIME type by file extension.
    public subscript(fileExtension: String) -> String? {
        get { mimeTypes[Self.normalizedExtension(fileExtension)] }
        set { mimeTypes[Self.normalizedExtension(fileExtension)] = newValue }
    }

    /// Registers `mimeType` for `fileExtension`.
    public mutating func register(_ mimeType: String, for fileExtension: String) {
        self[fileExtension] = mimeType
    }

    /// Registers all extension mappings in `mimeTypes`.
    public mutating func register(contentsOf mimeTypes: [String: String]) {
        for (fileExtension, mimeType) in mimeTypes {
            register(mimeType, for: fileExtension)
        }
    }

    /// Returns the MIME type for `fileExtension`, or `defaultMimeType` when unknown.
    public func mimeType(for fileExtension: String, default defaultMimeType: String = "application/octet-stream") -> String {
        mimeTypes[Self.normalizedExtension(fileExtension)] ?? defaultMimeType
    }

    /// Returns the MIME type for `url` by inspecting its path extension.
    public func mimeType(for url: URL, default defaultMimeType: String = "application/octet-stream") -> String {
        mimeType(for: url.pathExtension, default: defaultMimeType)
    }

    /// A default registry containing common web, document, media, and font types.
    public static let `default` = HTTPMimeTypeRegistry([
        "aac": "audio/aac",
        "abw": "application/x-abiword",
        "apng": "image/apng",
        "arc": "application/x-freearc",
        "avif": "image/avif",
        "avi": "video/x-msvideo",
        "azw": "application/vnd.amazon.ebook",
        "bin": "application/octet-stream",
        "bmp": "image/bmp",
        "bz": "application/x-bzip",
        "bz2": "application/x-bzip2",
        "cda": "application/x-cdf",
        "css": "text/css; charset=utf-8",
        "csv": "text/csv; charset=utf-8",
        "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "eot": "application/vnd.ms-fontobject",
        "epub": "application/epub+zip",
        "gz": "application/gzip",
        "gif": "image/gif",
        "htm": "text/html; charset=utf-8",
        "html": "text/html; charset=utf-8",
        "ico": "image/x-icon",
        "ics": "text/calendar; charset=utf-8",
        "jar": "application/java-archive",
        "jpeg": "image/jpeg",
        "jpg": "image/jpeg",
        "js": "application/javascript; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "jsonld": "application/ld+json; charset=utf-8",
        "map": "application/json; charset=utf-8",
        "md": "text/markdown; charset=utf-8",
        "mid": "audio/midi",
        "midi": "audio/midi",
        "mjs": "application/javascript; charset=utf-8",
        "mp3": "audio/mpeg",
        "mp4": "video/mp4",
        "mpeg": "video/mpeg",
        "mpkg": "application/vnd.apple.installer+xml",
        "odp": "application/vnd.oasis.opendocument.presentation",
        "ods": "application/vnd.oasis.opendocument.spreadsheet",
        "odt": "application/vnd.oasis.opendocument.text",
        "oga": "audio/ogg",
        "ogv": "video/ogg",
        "ogx": "application/ogg",
        "opus": "audio/opus",
        "otf": "font/otf",
        "pdf": "application/pdf",
        "php": "application/x-httpd-php",
        "png": "image/png",
        "ppt": "application/vnd.ms-powerpoint",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "rar": "application/vnd.rar",
        "rtf": "application/rtf",
        "sh": "application/x-sh",
        "svg": "image/svg+xml",
        "tar": "application/x-tar",
        "text": "text/plain; charset=utf-8",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "ts": "video/mp2t",
        "ttf": "font/ttf",
        "txt": "text/plain; charset=utf-8",
        "vsd": "application/vnd.visio",
        "wasm": "application/wasm",
        "weba": "audio/webm",
        "webm": "video/webm",
        "webmanifest": "application/manifest+json; charset=utf-8",
        "webp": "image/webp",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "xhtml": "application/xhtml+xml",
        "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "xml": "application/xml; charset=utf-8",
        "xul": "application/vnd.mozilla.xul+xml",
        "zip": "application/zip",
        "3gp": "video/3gpp",
        "3g2": "video/3gpp2",
        "7z": "application/x-7z-compressed"
    ])

    private static func normalizedExtension(_ fileExtension: String) -> String {
        fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    }
}
