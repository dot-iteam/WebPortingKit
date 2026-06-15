# Caching and Conditional Requests

Attach `Last-Modified`, `ETag`, and `Cache-Control` headers, then answer fresh requests with `304 Not Modified`.

## Overview

WebPortingKit exposes cache validation as value types:

- ``HTTPLastModified`` stores an HTTP-date-rounded modification time.
- ``HTTPETag`` stores an entity tag exactly as it appears in the header.
- ``HTTPCacheValidation`` groups optional `Last-Modified` and `ETag` validators.

The resource helpers use these APIs automatically: ``staticFile(request:from:pathPrefix:mimeTypes:defaultMimeType:cacheControl:)`` and ``bundleResource(request:in:subdirectory:pathPrefix:mimeTypes:defaultMimeType:cacheControl:)`` emit `Last-Modified` and `Cache-Control` (and answer `If-Modified-Since`); ``embeddedResource(request:resource:metadataStore:cacheControl:)`` additionally supports `ETag` validators.

## Last-Modified

HTTP dates have whole-second precision. ``HTTPLastModified`` rounds dates down before formatting.

```swift
let lastModified = HTTPLastModified(fileDate)

var headers = HTTPHeaders()
headers.add(lastModified: lastModified)
```

Use ``httpDateString(from:)`` and ``httpDate(from:)`` when manual formatting or parsing is needed.

## ETags

Use a constant ETag when the version is already known.

```swift
let validation = HTTPCacheValidation(
    lastModified: HTTPLastModified(fileDate),
    eTag: HTTPETag("\"asset-v1\"")
)
```

Use ``HTTPETagSource`` with embedded resources when the ETag is either fixed or generated from bytes.

```swift
let source = HTTPETagSource.generated(name: "sha256") { data in
    "\"asset-\(data.count)\""
}
```

Generated ETags can be cached per resource ID and generator name. Disable caching when the same ID can produce different bytes during a process lifetime.

```swift
let source = HTTPETagSource.generated(name: "timestamped", cache: false) { data in
    "\"dynamic-\(data.count)\""
}
```

## Building Headers

Use ``httpCacheHeaders(validation:cacheControl:)`` or `HTTPHeaders.add(cacheValidation:cacheControl:)` to serialize validators.

```swift
let headers = httpCacheHeaders(
    validation: validation,
    cacheControl: "public, max-age=60"
)
```

## Conditional Requests

Use ``isNotModified(request:validation:)`` to decide whether a response can be `304 Not Modified`.

```swift
if isNotModified(request: request, validation: validation) {
    return HTTPResponse(status: .notModified, headers: headers)
}
```

`If-None-Match` takes precedence over `If-Modified-Since`. If the request includes `If-None-Match` but the current resource has no ETag, the helper returns `false`.

## Recommended Cache Policies

For assets that may change but should revalidate cheaply, use the default resource helper policy:

```swift
"public, max-age=0, must-revalidate"
```

For fingerprinted assets such as `/assets/app.4b825dc.css`, use a long immutable policy:

```swift
"public, max-age=31536000, immutable"
```

For user-specific or sensitive responses, avoid public cache headers and prefer explicit private or no-store policies.
