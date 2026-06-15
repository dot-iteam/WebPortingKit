# ``WebPortingKit``

Build small Swift web servers on top of SwiftNIO with typed routing, request decoding, static resources, cache validation, cookies, redirects, and TLS.

## Overview

WebPortingKit is a high-level layer over SwiftNIO HTTP primitives. It keeps NIO's explicit request and response model, but provides the conveniences most applications need at the edge of a server:

- ``HTTPApplication`` and ``DefaultHTTPRoutingHandler`` for path-based routing.
- ``HTTPServer`` for serving plain HTTP or HTTPS with HTTP/1.1, HTTP/2, or ALPN negotiation.
- ``HTTPRequest`` and ``HTTPResponse`` as simple, Sendable request and response values.
- ``HTTPRequest/getForm(_:)`` for decoding JSON, `application/x-www-form-urlencoded`, and `multipart/form-data` bodies into a single model.
- ``MultipartFormDecoding`` and ``MultipartFile`` for decoding uploaded files directly into a `Decodable` model.
- ``staticFile(request:from:pathPrefix:mimeTypes:defaultMimeType:cacheControl:)``, ``bundleResource(request:in:subdirectory:pathPrefix:mimeTypes:defaultMimeType:cacheControl:)``, and ``embeddedResource(request:resource:metadataStore:cacheControl:)`` for serving assets safely.
- ``HTTPLastModified``, ``HTTPETag``, and ``HTTPCacheValidation`` for conditional requests and `304 Not Modified` responses.
- ``ResponseCookie`` and ``CookieOption`` for serializing response cookies.

The framework is intentionally small. A typical application creates an ``HTTPApplication``, registers routes and middleware, then starts an ``HTTPServer``.

```swift
import WebPortingKit

var app = HTTPApplication()

app.get("health") { _ in
    json(["status": "ok"])
}

let server = HTTPServer(identity: .http, app: app)

try await server.start(host: "127.0.0.1", port: 8080)
```

## Routing Model

The default router has two route styles:

- Exact routes, registered with methods such as `app.get(...)` or `handler.method(method:path:maximumBodySize:route:)`.
- Prefix routes, registered with methods such as `app.matchGet(...)` or `handler.matchMethod(method:path:maximumBodySize:route:)`.

Exact routes win before prefix routes. Route matching lowercases path components, so `/Users/Profile` and `/users/profile` match the same registered path.

```swift
var app = HTTPApplication()

app.get("users", "profile") { request in
    json(["path": request.normalizedPath.joined(separator: "/")])
}

app.matchGet("assets") { request in
    await staticFile(request: request, from: "/var/www", pathPrefix: ["assets"])
}
```

Middleware runs before both matched routes and the not-found handler. Return `.next` to continue, `.respond` to send the current response, or `.drop` to close the connection without writing a response.

```swift
app.middleware { context in
    guard context.request.headers.first(name: "x-api-key") == "secret" else {
        context.response.status = .unauthorized
        return .respond
    }
    return .next
}
```

## Request Bodies

Use ``HTTPRequest/getForm(_:)`` to decode the body into a model. It chooses the decoder from the request `Content-Type` — JSON, `application/x-www-form-urlencoded`, or `multipart/form-data` — and returns `nil` when the body is missing, the content type is unsupported, or decoding fails.

```swift
struct LoginForm: Decodable {
    let email: String
    let remember: Bool
}

app.post("login") { request in
    guard let form = request.getForm(LoginForm.self) else {
        return HTTPResponse(status: .badRequest)
    }
    return json(["email": form.email, "remember": form.remember])
}
```

For `multipart/form-data`, the same call fills file parts directly into the model. A property typed as `Data`, ``MultipartFile``, `[Data]`, or `[MultipartFile]` receives the uploaded file(s); scalar properties receive coerced text fields.

```swift
struct UploadFields: Decodable {
    let title: String
    let photo: [MultipartFile]
}

app.post("upload") { request in
    guard let form = request.getForm(UploadFields.self) else {
        return HTTPResponse(status: .badRequest)
    }
    return json(["title": form.title, "fileCount": form.photo.count])
}
```

The form decoder preserves strings that look like scalars. A field declared as `String` receives `"01234"`, `"true"`, or `"123456"` as a string. A field declared as `Int`, `Double`, `Bool`, or `Date` is parsed according to the destination type.

## Responses

Create response values directly with ``HTTPResponse/init(status:headers:body:)`` or use helper functions:

```swift
let html = Data("<h1>Hello</h1>".utf8).http(type: "text/html; charset=utf-8")
let created = json(["id": 42], status: .created)
let redirect = HTTPResponse(redirect: "/login", status: .seeOther)
```

Use `HTTPResponse.redirect(to:status:)` to convert an existing response into a redirect, and `HTTPHeaders.add(location:)` to add a `Location` header directly.

## Assets and Caching

Static files are served from a root directory after the route prefix is stripped from the request path. The helper rejects parent-directory traversal, encoded slashes, directories, and symlink escapes outside the served root.

```swift
app.staticFiles("assets", location: "/var/www/public")
```

Bundle resources use the same static file safety checks, rooted at a bundle resource directory.

```swift
app.bundleResources("docs", bundle: .module, subdirectory: "Documentation")
```

Embedded resources are useful for generated assets, built-in CSS or JavaScript, and small resources stored in code.

```swift
let css = EmbeddedHTTPResource(
    id: "site.css",
    mimeType: "text/css; charset=utf-8",
    eTag: .generated(name: "length") { data in
        "\"site-css-\(data.count)\""
    },
    data: { Data("body { font: system-ui; }".utf8) }
)

app.get("assets", "site.css") { request in
    await embeddedResource(request: request, resource: css)
}
```

Static, bundle, and embedded helpers attach cache validators by default and answer fresh conditional requests with `304 Not Modified`.

## TLS and Protocols

Plain servers use ``HTTPServerIdentity/http``. Secure servers use ``HTTPServerIdentity/secure(_:mode:)`` with ``SecureIdentityPair`` and ``HTTPSProtocolMode``.

```swift
let identity = SecureIdentityPair.pair(
    privateKey: .file("/etc/ssl/private/localhost-key.pem"),
    certificate: .file("/etc/ssl/certs/localhost.pem")
)

let server = HTTPServer(identity: .secure(identity, mode: .negotiated), app: app)

try await server.start(host: "0.0.0.0", port: 8443)
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:RoutingAndMiddleware>
- <doc:RequestsAndResponses>
- <doc:BodyDecoding>

### Assets and HTTP Semantics

- <doc:StaticAndEmbeddedResources>
- <doc:CachingAndConditionalRequests>
- <doc:CookiesRedirectsAndHeaders>
- <doc:TLSAndServerLifecycle>

### Guidance

- <doc:BestPractices>
- <doc:WebPortingKitTutorial>

### Core Types

- ``HTTPApplication``
- ``DefaultHTTPRoutingHandler``
- ``HTTPServer``
- ``HTTPRequest``
- ``HTTPResponse``
- ``HTTPContext``
- ``FormDataDecoding``
- ``FormDataDecoder``
- ``FormDataStorage``
- ``MultipartFormDecoding``
- ``MultipartFormDecoder``
- ``MultipartFormStorage``
- ``MultipartFile``
- ``parseFormURLValues(_:)``
- ``HTTPMimeTypeRegistry``
- ``ResponseCookie``
- ``HTTPCacheValidation``
- ``HTTPLastModified``
- ``HTTPETag``
- ``HTTPETagSource``
