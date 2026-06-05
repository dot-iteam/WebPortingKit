//
//  MultipartForm.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-30.
//

import Foundation
import RegexBuilder
public struct MultipartFormPart: CustomStringConvertible {
    public var name: String?
    public var headers: [String: String]
    public var contentDisposition: [String:String]
    public var filename: String?
    public var contentType: String?
    public var data: Data?
    public static func parseContentDisposition(value: String) -> [String:String] {
        let fileNameRegex = Local {
            Optionally {
                ";"
            }
            ZeroOrMore { .whitespace }
            "filename=\""
            Capture {
                ZeroOrMore {
                    CharacterClass.anyOf("\"").inverted
                }
            }
            "\""
        }
        let nameRegex = Local {
            "name=\""
            Capture {
                ZeroOrMore {
                    CharacterClass.anyOf("\"").inverted
                }
            }
            
            "\""
        }
        let regex = Regex {
            Anchor.startOfSubject
            ZeroOrMore(.whitespace)
            "form-data;"
            ZeroOrMore {
                .whitespace
            }
            Optionally {
                nameRegex
            }
            ZeroOrMore { .whitespace }
            Optionally {
                fileNameRegex
            }
        }
        
        var result: [String:String] = [:]
        let match = value.firstMatch(of: regex)
        result["name"] = match?.output.1?.description
        result["filename"] = match?.output.2?.description
        return result
    }
    public init(headers: [String : String], data: Data? = nil) {
        self.contentDisposition = Self.parseContentDisposition(value: headers["content-disposition"] ?? "")
        self.name = contentDisposition["name"]
        self.headers = headers
        self.filename = contentDisposition["filename"]
        self.contentType = headers["content-type"]
        self.data = data
        
    }
    public var description: String {
        guard data != nil else {
            return ""
        }
        return String(data: data!, encoding: .utf8) ?? ""
    }
}
public struct MultipartFormStream {
    public let data: Data
    public let boundary: Data
    var index: Int = 0
    public init?(data: Data, contentType: String) {
        self.data = data
        let regex = Regex {
            Anchor.startOfSubject
            "multipart/form-data;"
            ZeroOrMore {
                CharacterClass.whitespace
            }
            "boundary="
            Capture {
                ZeroOrMore {
                    CharacterClass.any
                }
            }
        }
        guard let match = contentType.firstMatch(of: regex) else {
            return nil
        }
        let boundary = match.output.1.description
        guard boundary.count > 0 else {
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
    mutating func nextBound(bound: Data) -> Bool {
       var lps = Array(repeating: 0, count: bound.count)
       var length = 0
       var i = 1
       while i < bound.count {
           if bound[i] == bound[length] {
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
            var byte = data[index]
            if byte >= 0x41 && byte <= 0x5a {
                byte |= 0x60
            }
            var boundByte = bound[boundIndex]
            if boundByte >= 0x41 && boundByte <= 0x5a {
                boundByte |= 0x60
            }
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
    public mutating func next() -> MultipartFormPart? {
        var beginIndex = index
        var part : MultipartFormPart
        if nextBound(bound: partSeparator) {
            part = MultipartFormPart(headers: parseBlockHeader(data: data[beginIndex..<index-partSeparator.count]))
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
            let value = match.output.2.description.lowercased().trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }
    
}
public func decodeMultipartFormData<T: Decodable>(type: T.Type = NoDecodableData.self, stream: inout MultipartFormStream) -> (files: [String: [MultipartFormPart]], form: T?) {
    var part: MultipartFormPart?
    var files = [String: [MultipartFormPart]]()
    var dictionary: [String: [Any?]] = [:]
    while true {
        part = stream.next()
        guard let part else { break }
        guard let name = part.name else { continue }
        if part.filename != nil || part.contentType != nil {
            files[name, default: []].append(part)
        } else {
            dictionary[name, default: []].append(parseFormEntryValue(data: part.data))
        }
    }
    var normalizedDictionary: [String: Any?] = [:]
    dictionary.forEach { key, value in
        if value.count == 1 {
            normalizedDictionary[key] = value.first
        } else {
            normalizedDictionary[key] = value
        }
    }
    let jsonData = try? JSONSerialization.data(
        withJSONObject: normalizedDictionary
    )
    var form: T? = nil
    if let jsonData {
        form = try? JSONDecoder().decode(T.self, from: jsonData)
    }
    return (files: files, form: form)
}
