# Best Practices

Build WebPortingKit services that are predictable, safe, and easy to test.

## Keep Route Boundaries Small

Prefer small route closures that validate input, call domain code, and build a response. Move business logic outside route closures so it can be unit tested without a server.

```swift
app.post("orders") { request in
    guard let input = request.getForm(CreateOrder.self) else {
        return HTTPResponse(status: .badRequest)
    }

    let order = try await orders.create(input)
    return json(order, status: .created)
}
```

## Use Typed Decoding

Prefer ``HTTPRequest/getForm(_:)`` over manual string parsing. Typed decoding keeps string fields as strings and only parses scalars when the destination property asks for a scalar.

```swift
struct ProfileForm: Decodable {
    let zipCode: String
    let age: Int
}
```

## Decode Files Into the Model

For multipart requests, ``HTTPRequest/getForm(_:)`` decodes uploaded files directly into the model — declare a property as `Data`, ``MultipartFile``, `[Data]`, or `[MultipartFile]`, and scalar properties for text fields. This keeps one model per request.

When you need the parts without going through a request, build a ``MultipartFormDecoding`` from a ``MultipartFormStream`` or a list of ``MultipartFile`` values.

## Set Body Limits

Set a server-wide maximum body size and lower per-route limits for endpoints that do not need large uploads.

```swift
var app = HTTPApplication(handler: DefaultHTTPRoutingHandler(maximumBodySize: 16 * 1024 * 1024))
app.post("profile", maximumBodySize: 64 * 1024) { request in
    HTTPResponse(status: .ok)
}
```

## Serve Files Through Helpers

Use ``staticFile(request:from:pathPrefix:mimeTypes:defaultMimeType:cacheControl:)`` and bundle resource helpers instead of hand-building file paths from request URLs. The helpers reject directory traversal, encoded slash components, directory responses, and symlink escapes.

## Do Blocking Work Off the Event Loop

The built-in static file helper reads metadata and bytes off the event loop. Follow the same rule in custom routes. If work blocks on disk, CPU-heavy operations, or external processes, move it away from NIO event-loop threads.

## Use Cache Validators

For assets and generated resources, attach validators and handle conditional requests. This reduces bandwidth and avoids unnecessary work.

```swift
let validation = HTTPCacheValidation(
    lastModified: HTTPLastModified(lastModifiedDate),
    eTag: HTTPETag("\"asset-v1\"")
)
let headers = httpCacheHeaders(validation: validation, cacheControl: "public, max-age=0, must-revalidate")

if isNotModified(request: request, validation: validation) {
    return HTTPResponse(status: .notModified, headers: headers)
}
```

## Avoid Unsafe Cookie Values

Use ``ResponseCookie`` and ``CookieOption`` instead of writing `Set-Cookie` by hand. The helper validates names, values, and option values before adding a header.

## Prefer Explicit Redirect Statuses

Use `.seeOther` after successful form submissions, `.temporaryRedirect` when preserving the method matters, and `.permanentRedirect` only when clients and caches should remember the target.

```swift
return HTTPResponse(redirect: "/orders/42", status: .seeOther)
```

## Choose TLS Mode Deliberately

Use ``HTTPSProtocolMode/negotiated`` for most HTTPS deployments. Use fixed HTTP/1.1 or HTTP/2 modes only when client compatibility or infrastructure requires it.

## Test Route Behavior Without a Socket

Most route behavior can be tested by building an ``HTTPContext`` and invoking ``HTTPRoutingHandler/routeWithDecision(context:)``. Reserve integration tests for server startup, TLS, protocol negotiation, and channel behavior.

## Keep Public APIs Documented

When adding a public type, function, property, or overload, add a concise symbol comment and a usage-level example in the relevant DocC article when the API creates a new workflow.
