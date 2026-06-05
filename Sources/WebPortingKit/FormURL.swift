//
//  Encoding.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation
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
    return nil
}
public func parseFormEntryValue(data: Data?) -> Any? {
    guard let data else {
        return nil
    }
    guard let value = String(data: data, encoding: .utf8) else {
        return data
    }
    return parseFormEntryValue(value: value)
}
public func decodeFormURL<Target: Decodable>(_ type: Target.Type, _ string: String) -> Target? {
    var urlComponents = URLComponents()
    urlComponents.percentEncodedQuery = string
    var dictionary = [String: [Any?]]()
    var normalizedDictionary: [String: Any?] = [:]
    urlComponents.queryItems?.forEach { entry in
        dictionary[entry.name, default: []].append(parseFormEntryValue(value: entry.value))
    }
    dictionary.forEach { key, value in
        if dictionary[key]?.count == 1 {
            normalizedDictionary[key] = value.first
        } else {
            normalizedDictionary[key] = value
        }
    }
    
    let jsonData = try? JSONSerialization.data(
        withJSONObject: normalizedDictionary
    )
    guard let jsonData else { return nil }
    return try? JSONDecoder().decode(Target.self, from: jsonData)
}
