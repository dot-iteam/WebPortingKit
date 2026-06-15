//
//  MultipartForm.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-30.
//

import Foundation
import RegexBuilder

/// A file-like part from a `multipart/form-data` request.
///
/// Decode parts into a `Decodable` model with ``MultipartFormDecoding``, where a property
/// typed as `Data`, ``MultipartFile``, `[Data]`, or `[MultipartFile]` receives the file(s).
public struct MultipartFile: CustomStringConvertible {
    /// The `name` parameter from `Content-Disposition`, if present.
    public var name: String?

    /// The part headers keyed by lowercased header name.
    public var headers: [String: String]

    /// Parsed parameters from the `Content-Disposition` header.
    public var contentDisposition: [String:String]

    /// The `filename` parameter from `Content-Disposition`, if present.
    public var filename: String?

    /// The part `Content-Type`, if present.
    public var contentType: String?

    /// The raw bytes for the part body.
    public var data: Data?

    /// Parses a `Content-Disposition: form-data` header into lowercased parameters.
    ///
    /// - Parameter value: The raw `Content-Disposition` header value.
    public static func parseContentDisposition(value: String) -> [String:String] {
        let mediaTypeRegex = Regex {
            Anchor.startOfSubject
            ZeroOrMore { CharacterClass.whitespace }
            "form-data"
            ZeroOrMore { CharacterClass.whitespace }
            Optionally { ";" }
        }
        guard value.firstMatch(of: mediaTypeRegex) != nil else {
            return [:]
        }

        let parameterRegex = Regex {
            Optionally { ";" }
            ZeroOrMore { CharacterClass.whitespace }
            Capture {
                OneOrMore {
                    CharacterClass(
                        CharacterClass.word,
                        CharacterClass.digit,
                        CharacterClass.anyOf("!#$%&'*+-.^_`|~")
                    )
                }
            }
            ZeroOrMore { CharacterClass.whitespace }
            "="
            ZeroOrMore { CharacterClass.whitespace }
            ChoiceOf {
                Regex {
                    "\""
                    Capture {
                        ZeroOrMore {
                            CharacterClass.anyOf("\"").inverted
                        }
                    }
                    "\""
                }
                Capture {
                    OneOrMore {
                        CharacterClass.anyOf(";").inverted
                    }
                }
            }
        }

        var result: [String:String] = [:]
        for match in value.matches(of: parameterRegex) {
            let key = match.output.1.description.lowercased()
            let quotedValue = match.output.2?.description
            let tokenValue = match.output.3?.description.trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = quotedValue ?? tokenValue
        }
        return result
    }

    /// Creates a multipart file part from parsed headers and optional body data.
    ///
    /// - Parameters:
    ///   - headers: Part headers keyed by lowercased header name.
    ///   - data: The raw part body bytes.
    public init(headers: [String : String], data: Data? = nil) {
        self.contentDisposition = Self.parseContentDisposition(value: headers["content-disposition"] ?? "")
        self.name = contentDisposition["name"]
        self.headers = headers
        self.filename = contentDisposition["filename"]
        self.contentType = headers["content-type"]
        self.data = data
    }

    /// A UTF-8 view of ``data`` for debugging, or an empty string when unavailable.
    public var description: String {
        guard let data else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// A streaming parser for `multipart/form-data` bodies held in memory.
public struct MultipartFormStream {
    /// The normalized body data parsed by the stream.
    public let data: Data

    /// The boundary marker used between parts, including the leading CRLF delimiter.
    public let boundary: Data

    var index: Int = 0

    /// Creates a multipart stream from body data and a `Content-Type` header.
    ///
    /// Returns `nil` when the content type is not `multipart/form-data`, the boundary
    /// parameter is missing, or the first boundary cannot be found in the body.
    public init?(data: Data, contentType: String) {
        self.data = Data(data)
        guard let boundary = Self.boundary(from: contentType) else {
            return nil
        }
        let firstBoundary = "--\(boundary)".data(using: .utf8) ?? Data()
        guard firstBoundary.count > 0 else {
            return nil
        }
        self.boundary = Data("\r\n--\(boundary)".utf8)
        guard nextBound(bound: firstBoundary) else {
            return nil
        }
    }

    private static func boundary(from contentType: String) -> String? {
        let mediaTypeRegex = Regex {
            Anchor.startOfSubject
            ZeroOrMore { CharacterClass.whitespace }
            "multipart/form-data"
                .regex.ignoresCase()
            ZeroOrMore { CharacterClass.whitespace }
            Optionally {
                ";"
            }
        }
        guard contentType.firstMatch(of: mediaTypeRegex) != nil else {
            return nil
        }

        let parameterRegex = Regex {
            Optionally {
                ";"
            }
            ZeroOrMore { CharacterClass.whitespace }
            Capture {
                OneOrMore {
                    CharacterClass(
                        CharacterClass.word,
                        CharacterClass.digit,
                        CharacterClass.anyOf("!#$%&'*+-.^_`|~")
                    )
                }
            }
            ZeroOrMore { CharacterClass.whitespace }
            "="
            ZeroOrMore { CharacterClass.whitespace }
            ChoiceOf {
                Regex {
                    "\""
                    Capture {
                        ZeroOrMore {
                            CharacterClass.anyOf("\"").inverted
                        }
                    }
                    "\""
                }
                Capture {
                    OneOrMore {
                        CharacterClass.anyOf(";").inverted
                    }
                }
            }
        }

        for match in contentType.matches(of: parameterRegex) {
            guard match.output.1.description.lowercased() == "boundary" else {
                continue
            }
            let quotedValue = match.output.2?.description
            let tokenValue = match.output.3?.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let boundary = quotedValue ?? tokenValue ?? ""
            return boundary.isEmpty ? nil : boundary
        }
        return nil
    }

    mutating func nextBound(bound: Data) -> Bool {
       var lps = Array(repeating: 0, count: bound.count)
       var length = 0
       var i = 1
       while i < bound.count {
           if bound[bound.startIndex + i] == bound[bound.startIndex + length] {
               length += 1
               lps[i] = length
               i += 1
           } else if length != 0 {
               length = lps[length - 1]
           } else {
               lps[i] = 0
               i += 1
           }
       }
        var boundIndex = 0
        while index < data.count {
            let byte = data[data.startIndex + index]
            let boundByte = bound[bound.startIndex + boundIndex]
            if byte == boundByte {
                if boundIndex == bound.count - 1 {
                    index += 1
                    return true
                } else {
                    boundIndex += 1
                }
                index += 1
            } else if boundIndex != 0 {
                boundIndex = lps[boundIndex - 1]
            } else {
                index += 1
            }
        }
        return false
    }

    let partSeparator = "\r\n\r\n".data(using: .utf8) ?? Data()
    let partDataSuffix = "\r\n".data(using: .utf8) ?? Data()

    /// Returns the next multipart part, or `nil` when the stream is exhausted.
    public mutating func next() -> MultipartFile? {
        var beginIndex = index
        var part : MultipartFile
        if nextBound(bound: partSeparator) {
            part = MultipartFile(
                headers: parseBlockHeader(
                    data: data[data.startIndex + beginIndex..<data.startIndex + index - partSeparator.count]
                )
            )
        } else {
            return nil
        }
        beginIndex = index
        if nextBound(bound: boundary) {
            part.data = data.subdata(in: data.startIndex+beginIndex..<data.startIndex+index-boundary.count)
        }
        return part
    }

    func parseBlockHeader(data: Data) -> [String: String] {
        guard let headersString = String(data: data, encoding: .utf8) else {
            return [:]
        }
        let regex = Regex {
            Anchor.startOfLine
            ZeroOrMore {
                CharacterClass.whitespace
            }
            Capture {
                OneOrMore {
                    CharacterClass(
                        CharacterClass.word,
                        CharacterClass.digit,
                        CharacterClass.anyOf("-_")
                    )
                }
            }
            ":"
            Capture {
                ZeroOrMore {
                    NegativeLookahead {
                        "\r\n"
                    }
                    CharacterClass.any
                }
            }
        }
        var result = [String: String]()
        let matches = headersString.matches(of: regex)
        for match in matches {
            let key = match.output.1.description.lowercased().trimmingCharacters(
                in: .whitespaces
            )
            let value = match.output.2.description.trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }
}
