import Foundation

/// Decodes a flat form-data dictionary (`[field: [values]]`) into a `Decodable`
/// value, driving the public ``FormDataDecoder``.
///
/// A field maps to a *list* of strings because form fields can repeat
/// (e.g. `tags=a&tags=b`). Scalar coercion happens lazily, against the target
/// type, so numeric-looking strings destined for `String` properties are left intact.
public struct FormDataDecoding {
    /// The decoded form fields, each mapping to its ordered list of raw string values.
    public var values: [String: [String]]
    /// Contextual information made available to `Decodable` types via `decoder.userInfo`.
    public var userInfo: [CodingUserInfoKey: Any]

    public init(values: [String: [String]], userInfo: [CodingUserInfoKey: Any] = [:]) {
        self.values = values
        self.userInfo = userInfo
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try FormDataDecoder(values: values, userInfo: userInfo).decode(type)
    }
}

/// The backing storage for a ``FormDataDecoder``.
///
/// A decoder holds either a keyed object — each field name mapped to its ordered list of
/// raw string values — or a single field's list of values, which backs arrays and nested
/// single values.
public enum FormDataStorage {
    /// A keyed object: each field name mapped to its ordered list of raw string values.
    case dictionary([String: [String]])

    /// A single field's ordered list of raw string values.
    case values([String])

    /// The first value when this is a ``values(_:)`` case, otherwise `nil`.
    public var firstValue: String? {
        switch self {
        case .dictionary:
            return nil
        case .values(let values):
            return values.first
        }
    }
}

/// A `Decoder` over a flat form-data payload.
///
/// Construct one with ``init(values:userInfo:)`` and call ``decode(_:)``, or hand it
/// directly to a `Decodable`'s `init(from:)`. The `userInfo` supplied here is
/// propagated to every nested decoder created while decoding.
public final class FormDataDecoder: Decoder {
    private let storage: FormDataStorage
    public let codingPath: [any CodingKey]
    public let userInfo: [CodingUserInfoKey: Any]

    fileprivate init(
        storage: FormDataStorage,
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) {
        self.storage = storage
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    public convenience init(values: [String: [String]], userInfo: [CodingUserInfoKey: Any] = [:]) {
        self.init(storage: .dictionary(values), codingPath: [], userInfo: userInfo)
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: self)
    }

    public func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .dictionary(let values) = storage else {
            throw DecodingError.typeMismatch(
                [String: [String]].self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected keyed form data")
            )
        }
        return KeyedDecodingContainer(
            FormDataKeyedDecodingContainer(values: values, codingPath: codingPath, userInfo: userInfo)
        )
    }

    public func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .values(let values) = storage else {
            throw DecodingError.typeMismatch(
                [String].self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected repeated form values")
            )
        }
        return FormDataUnkeyedDecodingContainer(values: values, codingPath: codingPath, userInfo: userInfo)
    }

    public func singleValueContainer() throws -> any SingleValueDecodingContainer {
        FormDataSingleValueDecodingContainer(value: storage.firstValue, codingPath: codingPath, userInfo: userInfo)
    }
}

private struct FormDataKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let values: [String: [String]]
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

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
        return try T(from: FormDataDecoder(storage: .values(keyValues), codingPath: codingPath + [key], userInfo: userInfo))
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
        return FormDataUnkeyedDecodingContainer(values: keyValues, codingPath: codingPath + [key], userInfo: userInfo)
    }

    func superDecoder() throws -> any Decoder {
        FormDataDecoder(storage: .dictionary(values), codingPath: codingPath, userInfo: userInfo)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        guard let keyValues = values[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Missing form field")
            )
        }
        return FormDataDecoder(storage: .values(keyValues), codingPath: codingPath + [key], userInfo: userInfo)
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
    let userInfo: [CodingUserInfoKey: Any]
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
        return try T(from: FormDataDecoder(storage: .values([value]), codingPath: elementPath, userInfo: userInfo))
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
        return FormDataDecoder(storage: .values([value]), codingPath: codingPath, userInfo: userInfo)
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
    let userInfo: [CodingUserInfoKey: Any]

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
        return try T(from: FormDataDecoder(storage: .values([rawValue()]), codingPath: codingPath, userInfo: userInfo))
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

enum FormDataScalar {
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

struct FormDataIndexKey: CodingKey {
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
