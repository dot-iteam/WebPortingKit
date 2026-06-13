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

        let decoded = try #require(request.getDecodedBody(type: StringPreservingForm.self))
        #expect(decoded == StringPreservingForm(zip: "01234", truthy: "true", number: "123456"))
    }

    @Test("request decodes form URL encoded body with string fields")
    func requestDecodesFormURLEncodedBodyWithStringFields() throws {
        let request = makeRequest(
            contentType: "application/x-www-form-urlencoded",
            body: "name=Abdul%20Rahman&age=31&admin=true&score=9.5"
        )

        let decoded = try #require(request.getDecodedBody(type: ProfileForm.self))
        #expect(decoded == ProfileForm(name: "Abdul Rahman", age: 31, admin: true, score: 9.5))
    }

    @Test("request form URL decoding treats plus as space and preserves encoded plus")
    func requestFormURLDecodingTreatsPlusAsSpaceAndPreservesEncodedPlus() throws {
        let request = makeRequest(
            contentType: "application/x-www-form-urlencoded",
            body: "name=John+Doe&q=a%2Bb"
        )

        let decoded = try #require(request.getDecodedBody(type: QueryForm.self))
        #expect(decoded == QueryForm(name: "John Doe", q: "a+b"))
    }

    @Test("request decodes form URL encoded body with content type parameters")
    func requestDecodesFormURLEncodedBodyWithContentTypeParameters() throws {
        let request = makeRequest(
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            body: "name=Abdul%20Rahman&age=31&admin=true&score=9.5"
        )

        let decoded = try #require(request.getDecodedBody(type: ProfileForm.self))
        #expect(decoded == ProfileForm(name: "Abdul Rahman", age: 31, admin: true, score: 9.5))
    }

    @Test("request decodes JSON body with content type parameters")
    func requestDecodesJSONBodyWithContentTypeParameters() throws {
        let request = makeRequest(
            contentType: "application/json; charset=utf-8",
            body: "{\"name\":\"Abdul Rahman\",\"age\":31,\"admin\":true,\"score\":9.5}"
        )

        let decoded = try #require(request.getDecodedBody(type: ProfileForm.self))
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

    @Test("getBody returns raw data when content type is missing")
    func getBodyReturnsRawDataWhenContentTypeIsMissing() throws {
        let request = makeRequest(contentType: nil, body: "raw-body")

        guard case .data(let data) = request.getBody(type: ProfileForm.self) else {
            Issue.record("Expected raw data body")
            return
        }
        #expect(String(decoding: try #require(data), as: UTF8.self) == "raw-body")
    }

    @Test("getBody callback receives decoded form body")
    func getBodyCallbackReceivesDecodedFormBody() throws {
        let request = makeRequest(
            contentType: "application/x-www-form-urlencoded",
            body: "name=Abdul%20Rahman&age=31&admin=true&score=9.5"
        )
        var decoded: ProfileForm?

        request.getBody(type: ProfileForm.self) { body in
            guard case .object(let value) = body else { return }
            decoded = value
        }

        #expect(decoded == ProfileForm(name: "Abdul Rahman", age: 31, admin: true, score: 9.5))
    }

    @Test("malformed JSON decodes to nil object")
    func malformedJSONDecodesToNilObject() {
        let request = makeRequest(contentType: "application/json", body: "{bad-json")

        guard case .object(let decoded) = request.getBody(type: ProfileForm.self) else {
            Issue.record("Expected object body")
            return
        }
        #expect(decoded == nil)
        #expect(request.getDecodedBody(type: ProfileForm.self) == nil)
    }

    @Test("getDecodedForm returns nil form for raw data")
    func getDecodedFormReturnsNilFormForRawData() {
        let request = makeRequest(contentType: "application/octet-stream", body: "raw")
        let decoded = request.getDecodedForm(type: ProfileForm.self)

        #expect(decoded.files.isEmpty)
        #expect(decoded.form == nil)
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
