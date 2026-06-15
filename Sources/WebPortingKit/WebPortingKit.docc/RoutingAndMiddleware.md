# Routing and Middleware

Use exact routes, prefix routes, middleware, and custom not-found handling to shape request flow.

## Overview

``DefaultHTTPRoutingHandler`` routes in this order:

1. Look up an exact route for the request method and normalized path.
2. Look up the first prefix route for the request method.
3. Run registered middleware.
4. Invoke the matched route or the not-found handler.
5. Return ``HTTPRoutingDecision/respond`` or ``HTTPRoutingDecision/drop``.

Exact routes take precedence over prefix routes. Middleware runs in registration order for matched routes and unmatched requests.

## Exact Routes

Register exact routes with method-specific helpers on ``HTTPApplication``.

```swift
app.get("posts") { _ in
    json(["items": []])
}

app.post("posts") { request in
    HTTPResponse(status: .created)
}
```

Use ``DefaultHTTPRoutingHandler/method(method:path:maximumBodySize:route:)`` when you are building or testing a router directly.

```swift
var router = DefaultHTTPRoutingHandler(maximumBodySize: 64 * 1024)
router.method(method: .GET, path: ["admin"], maximumBodySize: 8 * 1024) { context in
    context.response.status = .accepted
}
```

## Prefix Routes

Prefix routes are useful when a route owns every subpath below a prefix.

```swift
app.matchGet("api", "v1") { request in
    json(["matchedPath": request.path])
}
```

A request for `/api/v1/users/42` matches the route above.

## Middleware

Middleware can authenticate, attach context, add headers, block a request, or close the connection.

```swift
app.middleware { context in
    guard context.request.headers.first(name: "authorization") != nil else {
        context.response.status = .unauthorized
        return .respond
    }
    return .next
}
```

Use ``HTTPRequest/context`` for per-request data that later middleware or routes need.

```swift
struct User: Sendable {
    let id: String
}

app.middleware { context in
    await context.request.context.set(User(id: "123"), as: User.self)
    return .next
}

app.get("me") { request in
    let user = await request.context.get(User.self)
    return json(["id": user?.id ?? "anonymous"])
}
```

## Body Limits

Set an application-wide limit on the router, and narrower limits on routes that accept small payloads. The effective limit is the smaller of the two.

```swift
var router = DefaultHTTPRoutingHandler(maximumBodySize: 16 * 1024 * 1024)
router.method(method: .POST, path: ["profile"], maximumBodySize: 64 * 1024) { context in
    context.response.status = .ok
}
```

When a body exceeds the effective limit, the server returns `413 Payload Too Large` with an empty body.

## Not Found

A custom not-found handler can set headers and body. The router always forces the final status to `404 Not Found`.

```swift
app.notFound { _ in
    Data("Missing".utf8).http(type: "text/plain; charset=utf-8")
}
```
