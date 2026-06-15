# Tutorial: Build a Small Web Service

Create a WebPortingKit service with routes, middleware, typed body decoding, static assets, embedded resources, cookies, redirects, TLS, and clean shutdown.

## Overview

This tutorial builds one compact service in steps. The final application includes:

- A health route.
- Middleware that adds shared headers and protects selected routes.
- JSON and form decoding.
- Multipart uploads with files isolated from typed fields.
- Static and embedded assets with cache validators.
- Cookies and redirects.
- Plain HTTP and HTTPS startup examples.

## 1. Create the Application

Import the framework and create an application.

```swift
import Foundation
import WebPortingKit

var app = HTTPApplication()
```

Add a health route that returns JSON.

```swift
app.get("health") { _ in
    json(["status": "ok"])
}
```

Add a plain text route.

```swift
app.get("hello") { _ in
    Data("Hello from WebPortingKit".utf8)
        .http(type: "text/plain; charset=utf-8")
}
```

## 2. Add Middleware

Middleware runs before matched routes and before the not-found handler. Return `.next` to continue, `.respond` to send the current response, or `.drop` to close the connection.

```swift
app.middleware { context in
    context.response.headers.add(name: "x-powered-by", value: "WebPortingKit")
    return .next
}
```

Protect administrative routes by inspecting request headers.

```swift
app.middleware { context in
    guard context.request.path.contains("admin") else {
        return .next
    }

    guard context.request.headers.first(name: "x-api-key") == "secret" else {
        context.response.status = .unauthorized
        return .respond
    }

    return .next
}
```

## 3. Decode JSON and Form URL Encoded Bodies

Define a `Decodable` model.

```swift
struct ProfileForm: Decodable {
    let name: String
    let age: Int
    let zipCode: String
}
```

Use `getForm(_:)` for JSON, `application/x-www-form-urlencoded`, and multipart bodies. It picks the decoder from the request `Content-Type`.

```swift
app.post("profile") { request in
    guard let form = request.getForm(ProfileForm.self) else {
        return HTTPResponse(status: .badRequest)
    }

    return json([
        "name": form.name,
        "age": "\(form.age)",
        "zipCode": form.zipCode
    ])
}
```

Typed decoding preserves string values that look like scalars. If `zipCode` receives `01234`, it remains `"01234"` because the property is a `String`.

## 4. Decode Multipart Uploads

For `multipart/form-data`, the same `getForm(_:)` call fills file parts into the model. Declare a property as `Data`, `MultipartFile`, `[Data]`, or `[MultipartFile]` for uploads, and scalar properties for text fields.

```swift
struct UploadFields: Decodable {
    let title: String
    let file: [MultipartFile]
}

app.post("upload") { request in
    guard let fields = request.getForm(UploadFields.self) else {
        return HTTPResponse(status: .badRequest)
    }

    return json([
        "title": fields.title,
        "fileCount": "\(fields.file.count)"
    ])
}
```

Each `MultipartFile` contains normalized headers, field name, filename, content type, and bytes.

## 5. Serve Static Files

Register a static file tree with a prefix route.

```swift
app.staticFiles("assets", location: "/var/www/public")
```

A request for `/assets/css/site.css` maps to `/var/www/public/css/site.css`. The helper rejects traversal, encoded slash components, directories, and symlink escapes outside the root.

Customize MIME types when needed.

```swift
var mimeTypes = HTTPMimeTypeRegistry.default
mimeTypes.register("application/x-module", for: ".module")

app.staticFiles("assets", location: "/var/www/public", mimeTypes: mimeTypes)
```

## 6. Serve Embedded Resources

Use embedded resources for small generated or built-in assets.

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

The helper sends `Last-Modified`, optional `ETag`, and `Cache-Control` headers. Fresh conditional requests receive `304 Not Modified` without a body.

## 7. Add Cookies and Redirects

Return a redirect after login and attach a cookie.

```swift
app.post("login") { request in
    var response = HTTPResponse(redirect: "/dashboard", status: .seeOther)
    response.headers.add(cookie: ResponseCookie(
        name: "session",
        value: "abc123",
        options: .httpOnly, .secure, .sameSite(.lax), .path("/")
    ))
    return response
}
```

Read parsed request cookies from `request.cookies`.

```swift
app.get("dashboard") { request in
    guard request.cookies["session"] != nil else {
        return HTTPResponse(redirect: "/login", status: .seeOther)
    }

    return json(["signedIn": true])
}
```

## 8. Add a Not-Found Response

Customize unmatched routes. The router preserves the body and headers but forces the final status to `404 Not Found`.

```swift
app.notFound { _ in
    Data("Not found".utf8).http(type: "text/plain; charset=utf-8")
}
```

## 9. Start a Plain HTTP Server

Use plain HTTP for local development or when TLS terminates before the process.

```swift
let server = HTTPServer(identity: .http, app: app)

try await server.start(host: "127.0.0.1", port: 8080)
```

## 10. Start an HTTPS Server

Create a TLS identity pair and choose a protocol mode.

```swift
let identity = SecureIdentityPair.pair(
    privateKey: .file("/etc/ssl/private/server-key.pem"),
    certificate: .file("/etc/ssl/certs/server-fullchain.pem")
)

let secureServer = HTTPServer(identity: .secure(identity, mode: .negotiated), app: app)

try await secureServer.start(host: "0.0.0.0", port: 8443)
```

Use `.negotiated` for most HTTPS deployments so clients can use HTTP/2 or HTTP/1.1 through ALPN.

## 11. Stop Cleanly

Stop the bound server channel during shutdown or between tests.

```swift
await server.stop()
```

After `stop()` completes, the same server can be started again.

## Complete Sketch

```swift
import Foundation
import WebPortingKit

struct ProfileForm: Decodable {
    let name: String
    let age: Int
    let zipCode: String
}

var app = HTTPApplication()

app.middleware { context in
    context.response.headers.add(name: "x-powered-by", value: "WebPortingKit")
    return .next
}

app.get("health") { _ in
    json(["status": "ok"])
}

app.post("profile") { request in
    guard let form = request.getForm(ProfileForm.self) else {
        return HTTPResponse(status: .badRequest)
    }

    return json(["name": form.name, "zipCode": form.zipCode])
}

app.staticFiles("assets", location: "/var/www/public")

let server = HTTPServer(identity: .http, app: app)
try await server.start(host: "127.0.0.1", port: 8080)
```

## What to Read Next

- <doc:RoutingAndMiddleware>
- <doc:BodyDecoding>
- <doc:StaticAndEmbeddedResources>
- <doc:TLSAndServerLifecycle>
- <doc:BestPractices>
