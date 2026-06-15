//
//  Encoding.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation

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
    return try? FormDataDecoding(values: values).decode(Target.self)
}

/// Parses an `application/x-www-form-urlencoded` string into form fields.
///
/// `+` is decoded as a space and percent escapes are resolved by `URLComponents`. Repeated
/// field names accumulate into the value array, preserving their order. Use this to obtain
/// the raw `[field: [values]]` map — for example, to drive ``FormDataDecoding`` directly.
///
/// - Parameter string: The raw form-url-encoded body.
/// - Returns: Each field name mapped to its ordered list of decoded string values.
public func parseFormURLValues(_ string: String) -> [String: [String]] {
    var urlComponents = URLComponents()
    urlComponents.percentEncodedQuery = string.replacingOccurrences(of: "+", with: "%20")

    var values = [String: [String]]()
    urlComponents.queryItems?.forEach { entry in
        values[entry.name, default: []].append(entry.value ?? "")
    }
    return values
}
