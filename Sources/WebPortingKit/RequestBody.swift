//
//  RequestBody.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import Foundation
import RegexBuilder
public enum RequestBody<Body: Decodable> {
    case object(Body?)
    case multipartFormStream(MultipartFormStream?)
    case data(Data?)
}
public struct NoDecodableData: Decodable {
    
}
extension HTTPRequest {
    public func getBody<T: Decodable>(type: T.Type) -> RequestBody<T> {
        guard let body = self.body else {
            return .data(nil)
        }
        let contentType = self.headers.first(name: "content-type")?.lowercased()
        guard let contentType else {
            return .data(Data(buffer: body))
        }
        switch contentType {
            case "application/json":
            return .object(try? JSONDecoder().decode(T.self, from: Data(buffer: body)))
        case "application/x-www-form-urlencoded":
            return .object(decodeFormURL(T.self, body.getString(at: 0, length: body.readableBytes) ?? ""))
        default:
            if contentType.starts(with: "multipart/form-data;") {
                return .multipartFormStream(MultipartFormStream(data: Data(buffer: body), contentType: contentType))
            } else {
                return .data(Data(buffer: body))
            }
        }
    }
    public func getBody<T: Decodable>(type: T.Type, callback: (RequestBody<T>) -> Void) {
        callback(getBody(type: type))
    }
    public func getDecodedBody<T: Decodable>(type: T.Type) -> T? {
        switch getBody(type: type) {
        case .object(let value):
            return value
        case .multipartFormStream(var stream):
            guard stream != nil else {
                return nil
            }
            let (_, form) = decodeMultipartFormData(type: type, stream: &stream!)
            return form
        default:
            return nil
        }
    }
    public func getDecodedForm<T: Decodable>(type: T.Type) -> (files: [String: [MultipartFormPart]], form: T?) {
        switch getBody(type: type) {
        case .object(let value):
            return (files: [:], form: value)
        case .multipartFormStream(var stream):
            guard stream != nil else {
                return (files: [:], form: nil)
            }
            return decodeMultipartFormData(type: type, stream: &stream!)
        default:
            return (files: [:], form: nil)
        }
    }
}
