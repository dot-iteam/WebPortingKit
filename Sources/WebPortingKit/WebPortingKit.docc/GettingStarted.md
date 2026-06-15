# Getting Started

Create an application, register routes, and run a SwiftNIO-backed server.

## Overview

A WebPortingKit application has three layers:

1. ``HTTPApplication`` stores a routing handler.
2. ``DefaultHTTPRoutingHandler`` matches requests to middleware, exact routes, prefix routes, and a not-found route.
3. ``HTTPServer`` owns the network listener and converts NIO request frames into ``HTTPRequest`` values.

Start with a plain HTTP application during development.

```swift
import WebPortingKit

var app = HTTPApplication()

app.get("health") { _ in
    json(["status": "ok"])
}

app.get("hello") { _ in
    Data("Hello".utf8).http(type: "text/plain; charset=utf-8")
}

let server = HTTPServer(identity: .http, app: app)

try await server.start(host: "127.0.0.1", port: 8080)
```

## Register Routes

Exact routes match a complete normalized path.

```swift
app.get("users", "profile") { request in
    json(["path": request.normalizedPath])
}
```

Prefix routes match a path prefix and are useful for file trees or sub-applications.

```swift
app.matchGet("assets") { request in
    await staticFile(request: request, from: "/var/www/public", pathPrefix: ["assets"])
}
```

## Return Responses

Routes can return ``HTTPResponse`` directly, return `Data`, or mutate an ``HTTPContext`` depending on the overload you choose.

```swift
app.get("json") { _ in
    json(["message": "ok"])
}

app.get("bytes") { _ in
    Data("payload".utf8)
}

app.get("manual") { context in
    context.response.status = .accepted
    context.response.headers.add(name: "x-route", value: "manual")
}
```

## Stop and Restart

Use ``HTTPServer/stop()`` to close the bound server channel. You can start the same server instance again after a stop completes.

```swift
try await server.start(host: "127.0.0.1", port: 8080)
await server.stop()
try await server.start(host: "127.0.0.1", port: 8080)
```

## Next Steps

- Decode JSON and forms with <doc:BodyDecoding>.
- Serve assets with <doc:StaticAndEmbeddedResources>.
- Add TLS with <doc:TLSAndServerLifecycle>.
