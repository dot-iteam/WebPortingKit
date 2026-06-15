# TLS and Server Lifecycle

Run plain HTTP or HTTPS servers, select HTTP protocol behavior, and stop listeners cleanly.

## Plain HTTP

Use ``HTTPServerIdentity/http`` for local development or when TLS terminates before traffic reaches your process.

```swift
let server = HTTPServer(identity: .http, app: app)

try await server.start(host: "127.0.0.1", port: 8080)
```

Plain servers use HTTP/1.1.

## HTTPS

Use ``SecureIdentityPair`` to provide a private key and certificate chain from files, file URLs, or memory.

```swift
let pair = SecureIdentityPair.pair(
    privateKey: .file("/etc/ssl/private/server-key.pem"),
    certificate: .file("/etc/ssl/certs/server-fullchain.pem")
)
```

Then choose an ``HTTPSProtocolMode``.

```swift
let server = HTTPServer(identity: .secure(pair, mode: .negotiated), app: app)

try await server.start(host: "0.0.0.0", port: 8443)
```

Available modes:

- ``HTTPSProtocolMode/http1`` serves HTTP/1.1 over TLS.
- ``HTTPSProtocolMode/http2`` serves HTTP/2 over TLS.
- ``HTTPSProtocolMode/negotiated`` offers HTTP/2 and HTTP/1.1 with ALPN.

## Certificate Chain Order

Certificate files may contain a chain. Put the leaf certificate first, followed by intermediates moving toward the root. Do not include a self-signed root unless your deployment requires it.

## Lifecycle

Start the server once the application has registered all routes. `start(host:port:)` binds the listener and suspends until the server stops, so run it in its own task if you need to keep working.

```swift
try await server.start(host: "0.0.0.0", port: 8443)
```

Stop the bound server channel with ``HTTPServer/stop()``.

```swift
await server.stop()
```

After `stop()` completes, the same server can be started again. This is useful in tests and controlled lifecycle environments.

```swift
try await server.start(host: "0.0.0.0", port: 8443)
await server.stop()
try await server.start(host: "0.0.0.0", port: 8443)
```

## Body Limits

``HTTPServer/defaultMaximumBodySize`` is 16 MiB. Pass a custom server-wide limit through the `maximumBodySize:` initializer parameter (`HTTPServer(identity:maximumBodySize:app:)`) when accepted request sizes are smaller or larger. Route-level limits can further narrow the effective limit.

## Deployment Notes

- Prefer `.negotiated` for public HTTPS servers unless your clients require a fixed protocol.
- Keep TLS private keys outside the application bundle.
- Use a reverse proxy or platform load balancer when you need mature operational features such as automatic certificate renewal, request logging, and rate limiting.
- Treat graceful shutdown as part of application lifecycle: stop accepting new connections, finish important work, then call `stop()`.
