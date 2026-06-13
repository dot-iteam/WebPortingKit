import Foundation
import Testing
@testable import WebPortingKit

@Suite("Multipart form parsing")
struct MultipartFormTests {
    private struct UploadForm: Codable, Equatable {
        let field: String
    }

    private struct ScalarLookingMultipartForm: Codable, Equatable {
        let zip: String
        let enabled: String
        let count: Int
    }

    @Test("parses boundary parameter name case insensitively")
    func parsesBoundaryParameterNameCaseInsensitively() throws {
        let body = makeMultipartBody(boundary: "BoundaryABC", fieldValue: "value")

        var stream = try #require(
            MultipartFormStream(
                data: body,
                contentType: "multipart/form-data; Boundary=BoundaryABC"
            )
        )
        let decoded = decodeMultipartFormData(type: UploadForm.self, stream: &stream)

        #expect(decoded.form == UploadForm(field: "value"))
    }

    @Test("parses quoted boundary parameter value")
    func parsesQuotedBoundaryParameterValue() throws {
        let body = makeMultipartBody(boundary: "BoundaryABC", fieldValue: "value")

        var stream = try #require(
            MultipartFormStream(
                data: body,
                contentType: "multipart/form-data; boundary=\"BoundaryABC\""
            )
        )
        let decoded = decodeMultipartFormData(type: UploadForm.self, stream: &stream)

        #expect(decoded.form == UploadForm(field: "value"))
    }

    @Test("parses boundary parameter after other parameters")
    func parsesBoundaryParameterAfterOtherParameters() throws {
        let body = makeMultipartBody(boundary: "BoundaryABC", fieldValue: "value")

        var stream = try #require(
            MultipartFormStream(
                data: body,
                contentType: "multipart/form-data; charset=utf-8; boundary=BoundaryABC"
            )
        )
        let decoded = decodeMultipartFormData(type: UploadForm.self, stream: &stream)

        #expect(decoded.form == UploadForm(field: "value"))
    }

    @Test("matches body boundary value case sensitively")
    func matchesBodyBoundaryValueCaseSensitively() {
        let body = makeMultipartBody(boundary: "BoundaryABC", fieldValue: "value")

        let stream = MultipartFormStream(
            data: body,
            contentType: "multipart/form-data; boundary=boundaryabc"
        )

        #expect(stream == nil)
    }

    @Test("preserves multipart header values while normalizing header names")
    func preservesMultipartHeaderValuesWhileNormalizingHeaderNames() throws {
        let boundary = "BoundaryABC"
        let body = Data("""
        --\(boundary)\r
        Content-Disposition: form-data; name="UploadField"; filename="MyFile.TXT"\r
        Content-Type: Text/Plain\r
        \r
        file-body\r
        --\(boundary)--\r
        """.utf8)

        var stream = try #require(
            MultipartFormStream(
                data: body,
                contentType: "multipart/form-data; boundary=BoundaryABC"
            )
        )
        guard let part = stream.next() else {
            Issue.record("Expected multipart part")
            return
        }

        #expect(part.headers["content-disposition"] == "form-data; name=\"UploadField\"; filename=\"MyFile.TXT\"")
        #expect(part.name == "UploadField")
        #expect(part.filename == "MyFile.TXT")
        #expect(part.contentType == "Text/Plain")
    }

    @Test("parses content disposition parameters in any order")
    func parsesContentDispositionParametersInAnyOrder() {
        let part = MultipartFile(
            headers: [
                "content-disposition": "form-data; filename=\"MyFile.TXT\"; name=\"UploadField\"",
                "content-type": "Text/Plain"
            ],
            data: Data("file-body".utf8)
        )

        #expect(part.name == "UploadField")
        #expect(part.filename == "MyFile.TXT")
        #expect(part.contentType == "Text/Plain")
    }

    @Test("parses unquoted content disposition parameter values")
    func parsesUnquotedContentDispositionParameterValues() {
        let part = MultipartFile(
            headers: [
                "content-disposition": "form-data; name=UploadField; filename=MyFile.TXT"
            ],
            data: Data("file-body".utf8)
        )

        #expect(part.name == "UploadField")
        #expect(part.filename == "MyFile.TXT")
    }

    @Test("multipart stream accepts sliced data")
    func multipartStreamAcceptsSlicedData() throws {
        let body = makeMultipartBody(boundary: "BoundaryABC", fieldValue: "value")
        let padded = Data("prefix".utf8) + body + Data("suffix".utf8)
        let sliced = padded[padded.startIndex + 6..<padded.endIndex - 6]

        var stream = try #require(
            MultipartFormStream(
                data: sliced,
                contentType: "multipart/form-data; boundary=BoundaryABC"
            )
        )
        let decoded = decodeMultipartFormData(type: UploadForm.self, stream: &stream)

        #expect(decoded.form == UploadForm(field: "value"))
    }

    @Test("multipart form preserves string fields that look like scalars")
    func multipartFormPreservesStringFieldsThatLookLikeScalars() throws {
        let boundary = "BoundaryABC"
        let body = Data("""
        --\(boundary)\r
        Content-Disposition: form-data; name="zip"\r
        \r
        01234\r
        --\(boundary)\r
        Content-Disposition: form-data; name="enabled"\r
        \r
        true\r
        --\(boundary)\r
        Content-Disposition: form-data; name="count"\r
        \r
        12\r
        --\(boundary)--\r
        """.utf8)

        var stream = try #require(
            MultipartFormStream(
                data: body,
                contentType: "multipart/form-data; boundary=BoundaryABC"
            )
        )
        let decoded = decodeMultipartFormData(type: ScalarLookingMultipartForm.self, stream: &stream)

        #expect(decoded.files.isEmpty)
        #expect(decoded.form == ScalarLookingMultipartForm(zip: "01234", enabled: "true", count: 12))
    }

    @Test("multipart form keeps file parts separate from decoded fields")
    func multipartFormKeepsFilePartsSeparateFromDecodedFields() throws {
        let boundary = "BoundaryABC"
        let body = Data("""
        --\(boundary)\r
        Content-Disposition: form-data; name="field"\r
        \r
        value\r
        --\(boundary)\r
        Content-Disposition: form-data; name="upload"; filename="file.txt"\r
        Content-Type: text/plain\r
        \r
        file-body\r
        --\(boundary)--\r
        """.utf8)

        var stream = try #require(
            MultipartFormStream(
                data: body,
                contentType: "multipart/form-data; boundary=BoundaryABC"
            )
        )
        let decoded = decodeMultipartFormData(type: UploadForm.self, stream: &stream)

        #expect(decoded.form == UploadForm(field: "value"))
        let upload = try #require(decoded.files["upload"]?.first)
        #expect(upload.filename == "file.txt")
        #expect(upload.contentType == "text/plain")
        #expect(upload.description == "file-body")
    }

    @Test("rejects missing boundary parameter")
    func rejectsMissingBoundaryParameter() {
        let body = makeMultipartBody(boundary: "BoundaryABC", fieldValue: "value")

        let stream = MultipartFormStream(
            data: body,
            contentType: "multipart/form-data; charset=utf-8"
        )

        #expect(stream == nil)
    }

    private func makeMultipartBody(boundary: String, fieldValue: String) -> Data {
        Data("""
        --\(boundary)\r
        Content-Disposition: form-data; name="field"\r
        \r
        \(fieldValue)\r
        --\(boundary)--\r
        """.utf8)
    }
}
