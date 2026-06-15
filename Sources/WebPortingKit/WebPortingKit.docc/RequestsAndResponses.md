# Requests and Responses

Work with normalized requests, simple response values, JSON helpers, redirects, headers, trailers, and cookies.

## Requests

``HTTPRequest`` contains the URL, method, headers, body buffer, trailers, parsed cookies, and request context.

```swift
app.get("inspect") { request in
    json([
        "method": request.method.rawValue,
        "path": request.path.joined(separator: "/"),
        "normalizedPath": request.normalizedPath.joined(separator: "/")
    ])
}
```

Use ``HTTPRequest/path`` when preserving case matters. Use ``HTTPRequest/normalizedPath`` for route-like comparisons.

## Responses

``HTTPResponse`` is a mutable value with status, headers, body, and optional trailers.

```swift
var response = HTTPResponse(status: .accepted)
response.headers.add(name: "x-job", value: "queued")
```

Use helpers for common response bodies.

```swift
let text = Data("ok".utf8).http(type: "text/plain; charset=utf-8")
let payload = json(["ok": true])
let empty = HTTPResponse(status: .noContent)
```

``httpContent(status:type:headers:data:)`` is useful when response data is optional.

```swift
let response = httpContent(status: .ok, type: "application/octet-stream") {
    maybeLoadBytes()
}
```

## Redirects

Create redirects directly or mutate an existing response.

```swift
let created = HTTPResponse(redirect: "/login", status: .seeOther)

var response = HTTPResponse()
response.redirect(to: URL(string: "https://example.com/login")!)
```

The redirect helpers set status and replace the `Location` header together.

## Cookies

Request cookies are parsed from all `Cookie` headers into ``HTTPRequest/cookies``.

```swift
app.get("theme") { request in
    json(["theme": request.cookies["theme"] ?? "system"])
}
```

Add response cookies through ``ResponseCookie``.

```swift
var response = HTTPResponse(status: .ok)
response.headers.add(cookie: ResponseCookie(
    name: "session",
    value: "abc123",
    options: .httpOnly, .secure, .sameSite(.lax), .path("/")
))
```

Cookie names and values are validated before `Set-Cookie` is added. Invalid values are omitted instead of producing unsafe headers.

## Trailers

Route wrappers preserve trailers when a route returns a response with trailers. Use trailers for protocol-level metadata only when clients are known to support them.
