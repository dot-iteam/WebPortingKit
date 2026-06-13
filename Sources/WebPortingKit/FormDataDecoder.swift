import Foundation

struct FormDataDecoder {
    let values: [String: [String]]

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: _FormDataDecoder(storage: .dictionary(values), codingPath: []))
    }
}

private enum FormDataStorage {
    case dictionary([String: [String]])
    case values([String])

    var firstValue: String? {
        switch self {
        case .dictionary:
            return nil
        case .values(let values):
            return values.first
        }
    }
}

private final class _FormDataDecoder: Decoder {
    let storage: FormDataStorage
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any] = [:]

    init(storage: FormDataStorage, codingPath: [any CodingKey]) {
        self.storage = storage
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .dictionary(let values) = storage else {
            throw DecodingError.typeMismatch(
                [String: [String]].self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected keyed form data")
            )
        }
        return KeyedDecodingContainer(FormDataKeyedDecodingContainer(values: values, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .values(let values) = storage else {
            throw DecodingError.typeMismatch(
                [String].self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected repeated form values")
            )
        }
        return FormDataUnkeyedDecodingContainer(values: values, codingPath: codingPath)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        FormDataSingleValueDecodingContainer(value: storage.firstValue, codingPath: codingPath)
    }
}

private struct FormDataKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let values: [String: [String]]
    let codingPath: [any CodingKey]

    var allKeys: [Key] {
        values.keys.compactMap(Key.init(stringValue:))
    }

    func contains(_ key: Key) -> Bool {
        values[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        values[key.stringValue] == nil
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try rawValue(for: key)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try FormDataScalar.parse(type, from: rawValue(for: key), codingPath: codingPath + [key])
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        guard let keyValues = values[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Missing form field")
            )
        }
        if type == Date.self {
            return try FormDataScalar.parseDate(from: rawValue(for: key), codingPath: codingPath + [key]) as! T
        }
        return try T(from: _FormDataDecoder(storage: .values(keyValues), codingPath: codingPath + [key]))
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        throw DecodingError.typeMismatch(
            [String: [String]].self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Nested keyed form data is not supported")
        )
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard let keyValues = values[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Missing form field")
            )
        }
        return FormDataUnkeyedDecodingContainer(values: keyValues, codingPath: codingPath + [key])
    }

    func superDecoder() throws -> any Decoder {
        _FormDataDecoder(storage: .dictionary(values), codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        guard let keyValues = values[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Missing form field")
            )
        }
        return _FormDataDecoder(storage: .values(keyValues), codingPath: codingPath + [key])
    }

    private func rawValue(for key: Key) throws -> String {
        guard let value = values[key.stringValue]?.first else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Missing form field")
            )
        }
        return value
    }
}

private struct FormDataUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let values: [String]
    let codingPath: [any CodingKey]
    var currentIndex = 0
    var count: Int? { values.count }
    var isAtEnd: Bool { currentIndex >= values.count }

    mutating func decodeNil() throws -> Bool {
        false
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool {
        try decodeScalar(type)
    }

    mutating func decode(_ type: String.Type) throws -> String {
        try nextValue()
    }

    mutating func decode(_ type: Double.Type) throws -> Double {
        try decodeScalar(type)
    }

    mutating func decode(_ type: Float.Type) throws -> Float {
        try decodeScalar(type)
    }

    mutating func decode(_ type: Int.Type) throws -> Int {
        try decodeScalar(type)
    }

    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        try decodeScalar(type)
    }

    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        try decodeScalar(type)
    }

    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        try decodeScalar(type)
    }

    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        try decodeScalar(type)
    }

    mutating func decode(_ type: UInt.Type) throws -> UInt {
        try decodeScalar(type)
    }

    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        try decodeScalar(type)
    }

    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        try decodeScalar(type)
    }

    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        try decodeScalar(type)
    }

    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        try decodeScalar(type)
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let value = try nextValue()
        let elementPath = codingPath + [FormDataIndexKey(intValue: currentIndex - 1)]
        if type == Date.self {
            return try FormDataScalar.parseDate(from: value, codingPath: elementPath) as! T
        }
        return try T(from: _FormDataDecoder(storage: .values([value]), codingPath: elementPath))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        throw DecodingError.typeMismatch(
            [String: [String]].self,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Nested keyed form data is not supported")
        )
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch(
            [String].self,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Nested repeated form data is not supported")
        )
    }

    mutating func superDecoder() throws -> any Decoder {
        let value = try nextValue()
        return _FormDataDecoder(storage: .values([value]), codingPath: codingPath)
    }

    private mutating func decodeScalar<T>(_ type: T.Type) throws -> T where T: LosslessStringConvertible {
        let index = currentIndex
        let value = try nextValue()
        return try FormDataScalar.parse(type, from: value, codingPath: codingPath + [FormDataIndexKey(intValue: index)])
    }

    private mutating func nextValue() throws -> String {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "No more form values")
            )
        }
        defer { currentIndex += 1 }
        return values[currentIndex]
    }
}

private struct FormDataSingleValueDecodingContainer: SingleValueDecodingContainer {
    let value: String?
    let codingPath: [any CodingKey]

    func decodeNil() -> Bool {
        value == nil
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: String.Type) throws -> String {
        try rawValue()
    }

    func decode(_ type: Double.Type) throws -> Double {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: Float.Type) throws -> Float {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: Int.Type) throws -> Int {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        try FormDataScalar.parse(type, from: rawValue(), codingPath: codingPath)
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if type == Date.self {
            return try FormDataScalar.parseDate(from: rawValue(), codingPath: codingPath) as! T
        }
        return try T(from: _FormDataDecoder(storage: .values([rawValue()]), codingPath: codingPath))
    }

    private func rawValue() throws -> String {
        guard let value else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Missing form value")
            )
        }
        return value
    }
}

private enum FormDataScalar {
    static func parse<T>(_ type: T.Type, from value: String, codingPath: [any CodingKey]) throws -> T where T: LosslessStringConvertible {
        guard let parsed = T(value) else {
            throw DecodingError.typeMismatch(
                type,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected \(type) compatible form value")
            )
        }
        return parsed
    }

    static func parseDate(from value: String, codingPath: [any CodingKey]) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw DecodingError.typeMismatch(
                Date.self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected ISO 8601 date form value")
            )
        }
        return date
    }
}

private struct FormDataIndexKey: CodingKey {
    let intValue: Int?
    let stringValue: String

    init(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "Index \(intValue)"
    }

    init?(stringValue: String) {
        return nil
    }
}
