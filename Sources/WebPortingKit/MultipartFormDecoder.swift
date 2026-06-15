import Foundation

/// Decodes the parts of a `multipart/form-data` request into a `Decodable` value,
/// driving the public ``MultipartFormDecoder``.
///
/// Unlike ``FormDataDecoding`` (which only sees text fields), this driver keeps the
/// raw parts, so a target type can mix text fields with file parts. A property may be:
///
/// - a scalar (`String`, `Int`, `Bool`, `Double`, `Date`, …) — coerced from the part's
///   UTF-8 text, lazily against the target type;
/// - `Data` — the part's raw bytes;
/// - ``MultipartFile`` — the whole part (headers, filename, content type, bytes);
/// - `[Data]` / `[MultipartFile]` — every part sharing that field name.
public struct MultipartFormDecoding {
    /// The parts to decode, in the order they appeared in the request.
    public var parts: [MultipartFile]
    /// Contextual information made available to `Decodable` types via `decoder.userInfo`.
    public var userInfo: [CodingUserInfoKey: Any]

    public init(parts: [MultipartFile], userInfo: [CodingUserInfoKey: Any] = [:]) {
        self.parts = parts
        self.userInfo = userInfo
    }

    /// Drains a copy of `stream` into a list of parts and decodes from it.
    public init(stream: MultipartFormStream, userInfo: [CodingUserInfoKey: Any] = [:]) {
        var stream = stream
        var collected: [MultipartFile] = []
        while let part = stream.next() {
            collected.append(part)
        }
        self.init(parts: collected, userInfo: userInfo)
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try MultipartFormDecoder(parts: parts, userInfo: userInfo).decode(type)
    }
}

/// The backing storage for a ``MultipartFormDecoder``.
///
/// A decoder holds either a keyed object — each field name mapped to the parts that share
/// it — or a single field's list of parts, which backs arrays and nested single values.
public enum MultipartFormStorage {
    /// A keyed object: each field name mapped to the parts that share it.
    case dictionary([String: [MultipartFile]])

    /// A single field's parts, used for arrays and nested single values.
    case parts([MultipartFile])

    /// The first part when this is a ``parts(_:)`` case, otherwise `nil`.
    public var firstPart: MultipartFile? {
        switch self {
        case .dictionary:
            return nil
        case .parts(let parts):
            return parts.first
        }
    }
}

/// A `Decoder` over the parts of a `multipart/form-data` request.
///
/// Construct one with ``init(parts:userInfo:)`` and call ``decode(_:)``, or hand it to a
/// `Decodable`'s `init(from:)`. Beyond the scalar coercion that ``FormDataDecoder``
/// performs, this decoder also yields `Data`, ``MultipartFile``, `[Data]`, and
/// `[MultipartFile]` directly from the request's file parts.
public final class MultipartFormDecoder: Decoder {
    private let storage: MultipartFormStorage
    public let codingPath: [any CodingKey]
    public let userInfo: [CodingUserInfoKey: Any]

    fileprivate init(
        storage: MultipartFormStorage,
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) {
        self.storage = storage
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    /// Creates a decoder from an ordered list of parts, grouping them by field name.
    public convenience init(parts: [MultipartFile], userInfo: [CodingUserInfoKey: Any] = [:]) {
        var grouped: [String: [MultipartFile]] = [:]
        for part in parts {
            guard let name = part.name else { continue }
            grouped[name, default: []].append(part)
        }
        self.init(storage: .dictionary(grouped), codingPath: [], userInfo: userInfo)
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: self)
    }

    public func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .dictionary(let values) = storage else {
            throw DecodingError.typeMismatch(
                [String: [MultipartFile]].self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected keyed multipart data")
            )
        }
        return KeyedDecodingContainer(
            MultipartFormKeyedDecodingContainer(values: values, codingPath: codingPath, userInfo: userInfo)
        )
    }

    public func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .parts(let parts) = storage else {
            throw DecodingError.typeMismatch(
                [MultipartFile].self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected repeated multipart parts")
            )
        }
        return MultipartFormUnkeyedDecodingContainer(parts: parts, codingPath: codingPath, userInfo: userInfo)
    }

    public func singleValueContainer() throws -> any SingleValueDecodingContainer {
        MultipartFormSingleValueDecodingContainer(part: storage.firstPart, codingPath: codingPath, userInfo: userInfo)
    }
}

/// The UTF-8 text of a part's body, or `nil` when it is absent or not valid UTF-8.
func multipartText(_ part: MultipartFile) -> String? {
    part.data.flatMap { String(data: $0, encoding: .utf8) }
}

private struct MultipartFormKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let values: [String: [MultipartFile]]
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
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try text(for: key)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try FormDataScalar.parse(type, from: text(for: key), codingPath: path(for: key))
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let parts = try parts(for: key)
        if type == MultipartFile.self {
            return try requireFirst(parts, key: key) as! T
        }
        if type == [MultipartFile].self {
            return parts as! T
        }
        if type == Data.self {
            return try requireData(requireFirst(parts, key: key), key: key) as! T
        }
        if type == [Data].self {
            return try parts.map { try requireData($0, key: key) } as! T
        }
        if type == Date.self {
            return try FormDataScalar.parseDate(from: text(for: key), codingPath: path(for: key)) as! T
        }
        return try T(from: MultipartFormDecoder(storage: .parts(parts), codingPath: path(for: key), userInfo: userInfo))
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        throw DecodingError.typeMismatch(
            [String: [MultipartFile]].self,
            DecodingError.Context(codingPath: path(for: key), debugDescription: "Nested keyed multipart data is not supported")
        )
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        MultipartFormUnkeyedDecodingContainer(values: try parts(for: key), codingPath: path(for: key), userInfo: userInfo)
    }

    func superDecoder() throws -> any Decoder {
        MultipartFormDecoder(storage: .dictionary(values), codingPath: codingPath, userInfo: userInfo)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        MultipartFormDecoder(storage: .parts(try parts(for: key)), codingPath: path(for: key), userInfo: userInfo)
    }

    private func path(for key: Key) -> [any CodingKey] {
        codingPath + [key]
    }

    private func parts(for key: Key) throws -> [MultipartFile] {
        guard let parts = values[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Missing multipart field")
            )
        }
        return parts
    }

    private func requireFirst(_ parts: [MultipartFile], key: Key) throws -> MultipartFile {
        guard let part = parts.first else {
            throw DecodingError.valueNotFound(
                MultipartFile.self,
                DecodingError.Context(codingPath: path(for: key), debugDescription: "Multipart field has no parts")
            )
        }
        return part
    }

    private func requireData(_ part: MultipartFile, key: Key) throws -> Data {
        guard let data = part.data else {
            throw DecodingError.valueNotFound(
                Data.self,
                DecodingError.Context(codingPath: path(for: key), debugDescription: "Multipart part has no data")
            )
        }
        return data
    }

    private func text(for key: Key) throws -> String {
        let part = try requireFirst(parts(for: key), key: key)
        guard let text = multipartText(part) else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: path(for: key), debugDescription: "Expected a UTF-8 text multipart field")
            )
        }
        return text
    }
}

private struct MultipartFormUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let parts: [MultipartFile]
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    var currentIndex = 0

    init(parts: [MultipartFile], codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.parts = parts
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    init(values: [MultipartFile], codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.init(parts: values, codingPath: codingPath, userInfo: userInfo)
    }

    var count: Int? { parts.count }
    var isAtEnd: Bool { currentIndex >= parts.count }

    mutating func decodeNil() throws -> Bool {
        false
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try decodeScalar(type) }
    mutating func decode(_ type: String.Type) throws -> String { try text(for: nextPart()) }
    mutating func decode(_ type: Double.Type) throws -> Double { try decodeScalar(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try decodeScalar(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try decodeScalar(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try decodeScalar(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try decodeScalar(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try decodeScalar(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try decodeScalar(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try decodeScalar(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeScalar(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeScalar(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeScalar(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeScalar(type) }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let part = try nextPart()
        let elementPath = codingPath + [FormDataIndexKey(intValue: currentIndex - 1)]
        if type == MultipartFile.self {
            return part as! T
        }
        if type == Data.self {
            guard let data = part.data else {
                throw DecodingError.valueNotFound(Data.self, DecodingError.Context(codingPath: elementPath, debugDescription: "Multipart part has no data"))
            }
            return data as! T
        }
        if type == Date.self {
            return try FormDataScalar.parseDate(from: text(for: part), codingPath: elementPath) as! T
        }
        return try T(from: MultipartFormDecoder(storage: .parts([part]), codingPath: elementPath, userInfo: userInfo))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        throw DecodingError.typeMismatch(
            [String: [MultipartFile]].self,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Nested keyed multipart data is not supported")
        )
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch(
            [MultipartFile].self,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Nested repeated multipart data is not supported")
        )
    }

    mutating func superDecoder() throws -> any Decoder {
        MultipartFormDecoder(storage: .parts([try nextPart()]), codingPath: codingPath, userInfo: userInfo)
    }

    private mutating func decodeScalar<T>(_ type: T.Type) throws -> T where T: LosslessStringConvertible {
        let index = currentIndex
        let part = try nextPart()
        return try FormDataScalar.parse(type, from: text(for: part), codingPath: codingPath + [FormDataIndexKey(intValue: index)])
    }

    private mutating func nextPart() throws -> MultipartFile {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                MultipartFile.self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "No more multipart parts")
            )
        }
        defer { currentIndex += 1 }
        return parts[currentIndex]
    }

    private func text(for part: MultipartFile) throws -> String {
        guard let text = multipartText(part) else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected a UTF-8 text multipart part")
            )
        }
        return text
    }
}

private struct MultipartFormSingleValueDecodingContainer: SingleValueDecodingContainer {
    let part: MultipartFile?
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    func decodeNil() -> Bool {
        part == nil
    }

    func decode(_ type: Bool.Type) throws -> Bool { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: String.Type) throws -> String { try text() }
    func decode(_ type: Double.Type) throws -> Double { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: Float.Type) throws -> Float { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: Int.Type) throws -> Int { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: Int8.Type) throws -> Int8 { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: Int16.Type) throws -> Int16 { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: Int32.Type) throws -> Int32 { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: Int64.Type) throws -> Int64 { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: UInt.Type) throws -> UInt { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try FormDataScalar.parse(type, from: text(), codingPath: codingPath) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let part = try requirePart()
        if type == MultipartFile.self {
            return part as! T
        }
        if type == Data.self {
            guard let data = part.data else {
                throw DecodingError.valueNotFound(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Multipart part has no data"))
            }
            return data as! T
        }
        if type == Date.self {
            return try FormDataScalar.parseDate(from: text(), codingPath: codingPath) as! T
        }
        return try T(from: MultipartFormDecoder(storage: .parts([part]), codingPath: codingPath, userInfo: userInfo))
    }

    private func requirePart() throws -> MultipartFile {
        guard let part else {
            throw DecodingError.valueNotFound(
                MultipartFile.self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Missing multipart part")
            )
        }
        return part
    }

    private func text() throws -> String {
        guard let text = multipartText(try requirePart()) else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Expected a UTF-8 text multipart part")
            )
        }
        return text
    }
}

extension MultipartFile: Decodable {
    /// `MultipartFile` is only meaningful when decoded by ``MultipartFormDecoder``, which
    /// intercepts it directly. Reaching this initializer means an unsupported decoder.
    public init(from decoder: any Decoder) throws {
        throw DecodingError.typeMismatch(
            MultipartFile.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "MultipartFile can only be decoded with MultipartFormDecoder"
            )
        )
    }
}
