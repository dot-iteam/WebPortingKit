# Cookies, Redirects, and Headers

Use helpers for common HTTP header workflows while keeping direct access to `HTTPHeaders`.

## Cookies

``ResponseCookie`` combines a name, value, and ordered ``CookieOption`` values.

```swift
var response = HTTPResponse(status: .ok)
response.headers.add(cookie: ResponseCookie(
    name: "session",
    value: "abc123",
    options: .httpOnly, .secure, .sameSite(.lax), .path("/")
))
```

Invalid cookie names, invalid cookie values, and invalid option values are rejected by omitting the `Set-Cookie` header. This prevents common response splitting and malformed-cookie mistakes.

Use ``getRequestCookies(headers:)`` when manually parsing cookies from headers. Route handlers can usually read ``HTTPRequest/cookies`` directly.

```swift
let theme = request.cookies["theme"] ?? "system"
```

## Redirects

Create a redirect response in one call.

```swift
return HTTPResponse(redirect: "/login", status: .seeOther)
```

Update an existing response when other code has already prepared headers.

```swift
var response = HTTPResponse()
response.redirect(to: URL(string: "https://example.com/login")!, status: .temporaryRedirect)
```

## Header Helpers

The framework adds focused helpers to `HTTPHeaders` for common response fields:

```swift
var headers = HTTPHeaders()
headers.add(location: "/target")
headers.add(cacheControl: "public, max-age=60")
headers.add(eTag: HTTPETag("\"v1\""))
headers.add(lastModified: HTTPLastModified(Date()))
```

These helpers do not hide `HTTPHeaders`. Use NIO's regular methods when you need arbitrary fields.

```swift
response.headers.replaceOrAdd(name: "content-language", value: "en")
```

## Request Cookie Capture

``HTTPRequestCookieCapture`` is a property-wrapper-style type that parses cookie headers into a dictionary.

```swift
let capture = HTTPRequestCookieCapture(wrappedValue: [:], headers: request.headers)
let cookies = capture.wrappedValue
```

Most application code should prefer ``HTTPRequest/cookies`` unless it is adapting another API that expects this wrapper form.
