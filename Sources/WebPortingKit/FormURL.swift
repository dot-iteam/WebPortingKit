//
//  Encoding.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation

/// Parses a form field value using eager scalar coercion.
///
/// This API is retained for source compatibility. Prefer ``decodeFormURL(_:_:)`` so
/// values are coerced using the target `Decodable` property type instead of being
/// guessed before the destination type is known.
@available(*, deprecated, message: "Use decodeFormURL(_:_:), getDecodedBody(type:), or getDecodedForm(type:) so values are coerced using the target Decodable type.")
public func parseFormEntryValue(value: String?) -> Any? {
    guard let value else {
        return nil
    }
    let intValue = Int(value)
    if let intValue {
        return intValue
    }
    let doubleValue = Double(value)
    if let doubleValue {
        return doubleValue
    }
    let boolValue = Bool(value)
    if let boolValue {
        return boolValue
    }
    let dateValue = ISO8601DateFormatter().date(from: value)
    if let dateValue {
        return dateValue
    }
    return value
}

/// Parses UTF-8 form field bytes using eager scalar coercion.
///
/// This API is retained for source compatibility. Prefer ``decodeFormURL(_:_:)`` so
/// values are coerced using the target `Decodable` property type.
@available(*, deprecated, message: "Use decodeFormURL(_:_:), getDecodedBody(type:), or getDecodedForm(type:) so values are coerced using the target Decodable type.")
public func parseFormEntryValue(data: Data?) -> Any? {
    guard let data else {
        return nil
    }
    guard let value = String(data: data, encoding: .utf8) else {
        return data
    }
    return parseFormEntryValue(value: value)
}

/// Decodes an `application/x-www-form-urlencoded` body into a `Decodable` value.
///
/// The parser follows form-url-encoded rules: `+` represents a space and percent
/// escapes are decoded by `URLComponents`. Repeated field names decode as arrays
/// when the target property requests an array.
///
/// - Parameters:
///   - type: The expected Swift model type.
///   - string: The raw form-url-encoded body.
/// - Returns: The decoded value, or `nil` when parsing or decoding fails.
public func decodeFormURL<Target: Decodable>(_ type: Target.Type, _ string: String) -> Target? {
    let values = parseFormURLValues(string)
    return try? FormDataDecoder(values: values).decode(Target.self)
}

private func parseFormURLValues(_ string: String) -> [String: [String]] {
    var urlComponents = URLComponents()
    urlComponents.percentEncodedQuery = string.replacingOccurrences(of: "+", with: "%20")

    var values = [String: [String]]()
    urlComponents.queryItems?.forEach { entry in
        values[entry.name, default: []].append(entry.value ?? "")
    }
    return values
}
