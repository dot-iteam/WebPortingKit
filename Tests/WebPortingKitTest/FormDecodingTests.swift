import Foundation
import NIOCore
import NIOHTTP1
import Testing
@testable import WebPortingKit

@Suite("Request body decoding")
struct RequestBodyDecodingTests {
    private struct ProfileForm: Codable, Equatable {
        let name: String
        let age: Int
        let admin: Bool
        let score: Double
    }

    private struct QueryForm: Codable, Equatable {
        let name: String
        let q: String
    }

    private struct StringPreservingForm: Codable, Equatable {
        let zip: String
        let truthy: String
        let number: String
    }

    private struct RepeatedForm: Codable, Equatable {
        let tag: [String]
        let rank: [Int]
    }

    @Test("preserves plain string values while parsing typed scalar values")
    func preservesPlainStringValuesWhileParsingTypedScalarValues() throws {
        let decoded = try #require(
            decodeFormURL(
                ProfileForm.self,
                "name=Abdul%20Rahman&age=31&admin=true&score=9.5"
            )
        )

        #expect(decoded == ProfileForm(name: "Abdul Rahman", age: 31, admin: true, score: 9.5))
    }

    @Test("form URL decoder preserves string fields that look like scalars")
    func formURLDecoderPreservesStringFieldsThatLookLikeScalars() throws {
        let decoded = try #require(
            decodeFormURL(
                StringPreservingForm.self,
                "zip=01234&truthy=true&number=123456"
            )
        )

        #expect(decoded == StringPreservingForm(zip: "01234", truthy: "true", number: "123456"))
    }

    @Test("form URL decoder preserves repeated values and parses typed arrays")
    func formURLDecoderPreservesRepeatedValuesAndParsesTypedArrays() throws {
        let decoded = try #require(
            decodeFormURL(
                RepeatedForm.self,
                "tag=swift&tag=server&rank=1&rank=2"
            )
        )

        #expect(decoded == RepeatedForm(tag: ["swift", "server"], rank: [1, 2]))
    }

    @Test("form URL decoder treats plus as space and preserves encoded plus")
    func formURLDecoderTreatsPlusAsSpaceAndPreservesEncodedPlus() throws {
        let decoded = try #require(
            decodeFormURL(
                QueryForm.self,
                "name=John+Doe&q=a%2Bb"
            )
        )

        #expect(decoded == QueryForm(name: "John Doe", q: "a+b"))
    }

    @Test("request form URL decoding preserves string fields that look like scalars")
    func requestFormURLDecodingPreservesStringFieldsThatLookLikeScalars() throws {
        let request = makeRequest(
            contentType: "application/x-www-form-urlencoded",
            body: "zip=01234&truthy=true&number=123456"
        )

        let decoded = try #require(request.getForm(StringPreservingForm.self))
        #expect(decoded == StringPreservingForm(zip: "01234", truthy: "true", number: "123456"))
    }

    @Test("request decodes form URL encoded body with string fields")
    func requestDecodesFormURLEncodedBodyWithStringFields() throws {
        let request = makeRequest(
            contentType: "application/x-www-form-urlencoded",
            body: "name=Abdul%20Rahman&age=31&admin=true&score=9.5"
        )

        let decoded = try #require(request.getForm(ProfileForm.self))
        #expect(decoded == ProfileForm(name: "Abdul Rahman", age: 31, admin: true, score: 9.5))
    }

    @Test("request form URL decoding treats plus as space and preserves encoded plus")
    func requestFormURLDecodingTreatsPlusAsSpaceAndPreservesEncodedPlus() throws {
        let request = makeRequest(
            contentType: "application/x-www-form-urlencoded",
            body: "name=John+Doe&q=a%2Bb"
        )

        let decoded = try #require(request.getForm(QueryForm.self))
        #expect(decoded == QueryForm(name: "John Doe", q: "a+b"))
    }

    @Test("request decodes form URL encoded body with content type parameters")
    func requestDecodesFormURLEncodedBodyWithContentTypeParameters() throws {
        let request = makeRequest(
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            body: "name=Abdul%20Rahman&age=31&admin=true&score=9.5"
        )

        let decoded = try #require(request.getForm(ProfileForm.self))
        #expect(decoded == ProfileForm(name: "Abdul Rahman", age: 31, admin: true, score: 9.5))
    }

    @Test("request decodes JSON body with content type parameters")
    func requestDecodesJSONBodyWithContentTypeParameters() throws {
        let request = makeRequest(
            contentType: "application/json; charset=utf-8",
            body: "{\"name\":\"Abdul Rahman\",\"age\":31,\"admin\":true,\"score\":9.5}"
        )

        let decoded = try #require(request.getForm(ProfileForm.self))
        #expect(decoded == ProfileForm(name: "Abdul Rahman", age: 31, admin: true, score: 9.5))
    }

    @Test("request exposes path normalized path and URL components")
    func requestExposesPathNormalizedPathAndURLComponents() {
        let request = HTTPRequest(
            url: URL(string: "/Users/Profile?tab=Info")!,
            method: .GET,
            headers: HTTPHeaders(),
            body: nil,
            trailers: nil,
            cookies: [:]
        )

        #expect(request.path == ["/", "Users", "Profile"])
        #expect(request.normalizedPath == ["/", "users", "profile"])
        #expect(request.urlComponents.queryItems?.first?.name == "tab")
        #expect(request.urlComponents.queryItems?.first?.value == "Info")
    }

    @Test("malformed JSON decodes to nil")
    func malformedJSONDecodesToNil() {
        let request = makeRequest(contentType: "application/json", body: "{bad-json")

        #expect(request.getForm(ProfileForm.self) == nil)
    }

    private struct CSVPair: Decodable, Equatable {
        let name: String
        let age: Int
    }

    @Test("getForm fallback receives body and media type for unrecognized content type")
    func getFormFallbackHandlesUnrecognizedContentType() {
        let request = makeRequest(contentType: "text/csv; charset=utf-8", body: "Abdul,31")

        let decoded = request.getForm(CSVPair.self) { body, mediaType in
            #expect(mediaType == "text/csv")
            let fields = String(decoding: body, as: UTF8.self).split(separator: ",")
            guard fields.count == 2, let age = Int(fields[1]) else { return nil }
            return CSVPair(name: String(fields[0]), age: age)
        }

        #expect(decoded == CSVPair(name: "Abdul", age: 31))
    }

    @Test("getForm returns nil for unrecognized content type without a fallback")
    func getFormReturnsNilForUnrecognizedContentTypeWithoutFallback() {
        let request = makeRequest(contentType: "text/csv", body: "Abdul,31")

        #expect(request.getForm(CSVPair.self) == nil)
    }

    @Test("getForm async fallback decodes unrecognized content type")
    func getFormAsyncFallbackHandlesUnrecognizedContentType() async {
        let request = makeRequest(contentType: "text/csv; charset=utf-8", body: "Abdul,31")

        let decoded = await request.getForm(CSVPair.self) { body, mediaType in
            #expect(mediaType == "text/csv")
            // Simulate an asynchronous mapping source (e.g. a database lookup).
            try await Task.sleep(nanoseconds: 1_000)
            let fields = String(decoding: body, as: UTF8.self).split(separator: ",")
            guard fields.count == 2, let age = Int(fields[1]) else { return nil }
            return CSVPair(name: String(fields[0]), age: age)
        }

        #expect(decoded == CSVPair(name: "Abdul", age: 31))
    }

    @Test("getForm fallback receives nil media type when content type is missing")
    func getFormFallbackReceivesNilMediaTypeWhenContentTypeMissing() {
        let request = makeRequest(contentType: nil, body: "Abdul,31")

        let decoded = request.getForm(CSVPair.self) { body, mediaType in
            #expect(mediaType == nil)
            let fields = String(decoding: body, as: UTF8.self).split(separator: ",")
            guard fields.count == 2, let age = Int(fields[1]) else { return nil }
            return CSVPair(name: String(fields[0]), age: age)
        }

        #expect(decoded == CSVPair(name: "Abdul", age: 31))
    }

    @Test("getForm decodes multipart with a mixed-case boundary")
    func getFormDecodesMultipartWithMixedCaseBoundary() {
        struct Upload: Decodable {
            let field: String
        }
        let boundary = "BoundaryABC"
        let body = """
        --\(boundary)\r
        Content-Disposition: form-data; name="field"\r
        \r
        value\r
        --\(boundary)--\r
        """
        let request = makeRequest(contentType: "multipart/form-data; boundary=\(boundary)", body: body)

        // The boundary is case-sensitive; lowercasing the Content-Type would break this.
        #expect(request.getForm(Upload.self)?.field == "value")
    }

    @Test("getForm returns nil for raw data")
    func getFormReturnsNilForRawData() {
        let request = makeRequest(contentType: "application/octet-stream", body: "raw")

        #expect(request.getForm(ProfileForm.self) == nil)
    }

    private func makeRequest(contentType: String?, body: String) -> HTTPRequest {
        var headers = HTTPHeaders()
        if let contentType {
            headers.add(name: "content-type", value: contentType)
        }
        return HTTPRequest(
            url: URL(string: "/profile")!,
            method: .POST,
            headers: headers,
            body: ByteBufferAllocator().buffer(string: body),
            trailers: nil,
            cookies: [:]
        )
    }
}

@Suite("Form data decoder")
struct FormDataDecoderTests {
    private static let tagKey = CodingUserInfoKey(rawValue: "wpk.tag")!

    /// Reads its value straight from `decoder.userInfo` to prove propagation.
    private struct UserInfoProbe: Decodable {
        let tag: String
        init(from decoder: Decoder) throws {
            tag = decoder.userInfo[FormDataDecoderTests.tagKey] as? String ?? "missing"
        }
    }

    private struct Outer: Decodable {
        let inner: UserInfoProbe
    }

    private struct ScalarForm: Decodable, Equatable {
        let zip: String
        let age: Int
        let admin: Bool
    }

    @Test("public decoder coerces scalars against the target type")
    func coercesScalarsAgainstTargetType() throws {
        let decoder = FormDataDecoder(values: ["zip": ["01234"], "age": ["30"], "admin": ["true"]])

        let decoded = try decoder.decode(ScalarForm.self)

        // "01234" stays a String (leading zero preserved); "30" becomes Int; "true" becomes Bool.
        #expect(decoded == ScalarForm(zip: "01234", age: 30, admin: true))
    }

    @Test("userInfo is available to the root decoder")
    func userInfoReachesRootDecoder() throws {
        let driver = FormDataDecoding(values: [:], userInfo: [Self.tagKey: "present"])

        let probe = try driver.decode(UserInfoProbe.self)

        #expect(probe.tag == "present")
    }

    @Test("userInfo is propagated to nested decoders")
    func userInfoReachesNestedDecoders() throws {
        let driver = FormDataDecoding(values: ["inner": ["x"]], userInfo: [Self.tagKey: "present"])

        let outer = try driver.decode(Outer.self)

        // The nested field is decoded through a child FormDataDecoder; before the fix
        // its userInfo was empty and this would read "missing".
        #expect(outer.inner.tag == "present")
    }
}
