import Foundation
import Testing
@testable import WebPortingKit

@Suite("Multipart form decoder")
struct MultipartFormDecoderTests {
    private struct Upload: Decodable {
        let title: String
        let count: Int
        let avatar: Data
        let doc: MultipartFile
        let photos: [Data]
        let attachments: [MultipartFile]
    }

    private func textPart(name: String, value: String) -> MultipartFile {
        MultipartFile(
            headers: ["content-disposition": "form-data; name=\"\(name)\""],
            data: Data(value.utf8)
        )
    }

    private func filePart(name: String, filename: String, contentType: String, bytes: [UInt8]) -> MultipartFile {
        MultipartFile(
            headers: [
                "content-disposition": "form-data; name=\"\(name)\"; filename=\"\(filename)\"",
                "content-type": contentType
            ],
            data: Data(bytes)
        )
    }

    @Test("decodes scalars, Data, MultipartFile, and their arrays from parts")
    func decodesMixedFieldTypes() throws {
        let parts: [MultipartFile] = [
            textPart(name: "title", value: "Hello"),
            textPart(name: "count", value: "3"),
            filePart(name: "avatar", filename: "a.png", contentType: "image/png", bytes: [0, 1, 2, 3]),
            filePart(name: "doc", filename: "d.txt", contentType: "text/plain", bytes: Array("DOC".utf8)),
            filePart(name: "photos", filename: "p1.bin", contentType: "application/octet-stream", bytes: [10]),
            filePart(name: "photos", filename: "p2.bin", contentType: "application/octet-stream", bytes: [20]),
            filePart(name: "attachments", filename: "x.txt", contentType: "text/plain", bytes: Array("A".utf8)),
            filePart(name: "attachments", filename: "y.txt", contentType: "text/plain", bytes: Array("B".utf8)),
        ]

        let upload = try MultipartFormDecoding(parts: parts).decode(Upload.self)

        #expect(upload.title == "Hello")
        #expect(upload.count == 3)
        #expect(upload.avatar == Data([0, 1, 2, 3]))
        #expect(upload.doc.filename == "d.txt")
        #expect(upload.doc.contentType == "text/plain")
        #expect(upload.doc.data.flatMap { String(data: $0, encoding: .utf8) } == "DOC")
        #expect(upload.photos == [Data([10]), Data([20])])
        #expect(upload.attachments.count == 2)
        #expect(upload.attachments.map(\.filename) == ["x.txt", "y.txt"])
    }

    @Test("decodes from a multipart stream")
    func decodesFromStream() throws {
        let boundary = "BoundaryXYZ"
        let body = Data("""
        --\(boundary)\r
        Content-Disposition: form-data; name="title"\r
        \r
        Hello\r
        --\(boundary)\r
        Content-Disposition: form-data; name="file"; filename="a.txt"\r
        Content-Type: text/plain\r
        \r
        DATA\r
        --\(boundary)--\r
        """.utf8)
        let stream = try #require(
            MultipartFormStream(data: body, contentType: "multipart/form-data; boundary=\(boundary)")
        )

        struct StreamUpload: Decodable {
            let title: String
            let file: MultipartFile
        }

        let upload = try MultipartFormDecoding(stream: stream).decode(StreamUpload.self)

        #expect(upload.title == "Hello")
        #expect(upload.file.filename == "a.txt")
        #expect(upload.file.data.flatMap { String(data: $0, encoding: .utf8) } == "DATA")
    }

    @Test("missing optional file decodes to nil")
    func missingOptionalFileDecodesToNil() throws {
        struct OptionalUpload: Decodable {
            let title: String
            let avatar: Data?
        }

        let upload = try MultipartFormDecoding(parts: [textPart(name: "title", value: "Hi")])
            .decode(OptionalUpload.self)

        #expect(upload.title == "Hi")
        #expect(upload.avatar == nil)
    }

    @Test("userInfo propagates to the decoder")
    func userInfoPropagates() throws {
        let key = CodingUserInfoKey(rawValue: "wpk.tag")!
        struct Probe: Decodable {
            let tag: String
            init(from decoder: Decoder) throws {
                tag = decoder.userInfo[CodingUserInfoKey(rawValue: "wpk.tag")!] as? String ?? "missing"
            }
        }

        let probe = try MultipartFormDecoding(parts: [], userInfo: [key: "present"]).decode(Probe.self)

        #expect(probe.tag == "present")
    }
}
