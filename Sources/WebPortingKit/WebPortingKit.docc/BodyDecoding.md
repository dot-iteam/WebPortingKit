# Body Decoding

Decode JSON, form-url-encoded bodies, and multipart form data into Swift `Decodable` models.

## Overview

For most routes, use ``HTTPRequest/getForm(_:)``. It inspects the request `Content-Type` and decodes with the matching decoder, returning `nil` when the body is missing, the content type is unsupported, or decoding fails:

- `application/json` → `JSONDecoder`
- `application/x-www-form-urlencoded` → ``FormDataDecoding``
- `multipart/form-data` → ``MultipartFormDecoding`` (so the model may include `Data`, ``MultipartFile``, `[Data]`, or `[MultipartFile]` properties for uploaded files)

## JSON

```swift
struct CreatePost: Decodable {
    let title: String
    let published: Bool
}

app.post("posts") { request in
    guard let input = request.getForm(CreatePost.self) else {
        return HTTPResponse(status: .badRequest)
    }
    return json(["title": input.title, "published": input.published], status: .created)
}
```

## Form URL Encoding

`getForm(_:)` decodes `application/x-www-form-urlencoded` bodies automatically. String fields are preserved while values are coerced according to the destination property type.

```swift
struct SearchForm: Decodable {
    let q: String
    let page: Int
}

app.get("search") { request in
    request.getForm(SearchForm.self).map { json(["q": $0.q]) } ?? HTTPResponse(status: .badRequest)
}
```

To decode a form string directly, use ``decodeFormURL(_:_:)``. The `+` character is decoded as a space, and `%2B` remains a literal plus. Repeated field names decode into arrays when the target property requests an array.

```swift
struct TagsForm: Decodable {
    let tag: [String]
}

let tags = decodeFormURL(TagsForm.self, "tag=swift&tag=server")
```

## Multipart Forms

With `getForm(_:)`, a single `Decodable` model can mix typed fields and uploaded files. A property is filled according to its type:

| Property type | Value |
| --- | --- |
| scalar (`String`, `Int`, `Bool`, `Date`, …) | the field's UTF-8 text, coerced to the property type |
| `Data` | the part's raw bytes |
| ``MultipartFile`` | the whole part (headers, filename, content type, bytes) |
| `[Data]` / `[MultipartFile]` | every part sharing that field name |

```swift
struct Upload: Decodable {
    let title: String
    let publicFile: Bool
    let file: MultipartFile
    let gallery: [Data]
}

app.post("upload") { request in
    guard let upload = request.getForm(Upload.self) else {
        return HTTPResponse(status: .badRequest)
    }
    return json([
        "title": upload.title,
        "public": upload.publicFile,
        "filename": upload.file.filename ?? "",
        "images": upload.gallery.count
    ])
}
```

To decode the parts yourself, ``MultipartFormDecoding`` accepts a list of parts or a ``MultipartFormStream``.

## Custom Content Types

For any content type the built-in decoders do not recognize (or a request with no `Content-Type`), pass a `fallback` closure. It receives the raw body bytes and the lowercased media type — `nil` when the request had no `Content-Type` — and returns the decoded model.

```swift
struct CSVPair: Decodable {
    let name: String
    let age: Int
}

app.post("import") { request in
    let pair = request.getForm(CSVPair.self) { body, mediaType in
        guard mediaType == "text/csv" else { return nil }
        let fields = String(decoding: body, as: UTF8.self).split(separator: ",")
        guard fields.count == 2, let age = Int(fields[1]) else { return nil }
        return CSVPair(name: String(fields[0]), age: age)
    }
    return pair.map { json(["name": $0.name]) } ?? HTTPResponse(status: .unsupportedMediaType)
}
```

The `fallback` runs only for unrecognized content types; JSON, form-url-encoded, and multipart bodies always use the built-in decoders.

When mapping the body to the model needs asynchronous work — a database lookup, a configuration store, or any other async source — use the `async` overload with an `async` fallback:

```swift
app.post("import") { request in
    let pair = await request.getForm(CSVPair.self) { body, mediaType in
        guard mediaType == "text/csv" else { return nil }
        return try await store.parseCSVPair(body)
    }
    return pair.map { json(["name": $0.name]) } ?? HTTPResponse(status: .unsupportedMediaType)
}
```

## File-Only Multipart

When a route only needs uploaded files, decode into a model that contains just the file properties.

```swift
struct UploadedFiles: Decodable {
    let upload: [MultipartFile]
}

app.post("files") { request in
    let files = request.getForm(UploadedFiles.self)?.upload ?? []
    return json(["files": files.count])
}
```

## Scalar Coercion

Typed decoding coerces a field only when the destination property asks for a scalar. A field declared as `String` keeps values such as `"01234"`, `"true"`, or `"123456"` intact, while `Int`, `Double`, `Bool`, and `Date` properties parse the text according to the destination type. `Date` fields must be ISO 8601 text; other formats fail to decode.
