//
//  HTTPApplication.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import NIOHTTP1
import Foundation
public typealias HTTPRequestHandlerClosure = @Sendable (inout HTTPContext) async throws -> ()
public typealias HTTPRequestHandlerRouterClosure = @Sendable (HTTPRequest) async throws -> HTTPResponse
public typealias HTTPRequestHandlerDataRouteClosure = @Sendable (HTTPRequest) async throws -> Data
public typealias HTTPMiddlewareClosure = @Sendable (inout HTTPContext) async throws -> Bool
extension Data {
    public func http(type: String = "text/html; charset=utf-8") -> HTTPResponse {
        return HTTPResponse(status: .ok, headers: HTTPHeaders([("content-type", type)]), body: tryGetByteBuffer(
            data: self))
    }
}
public protocol HTTPRequestHandler: Sendable {
    func route(context: inout HTTPContext) async throws
}
public protocol HTTPMiddleware : Sendable {
    func route(context: inout HTTPContext) async throws -> Bool
}
public struct HTTPRequestHandlerClosureWrapper : HTTPRequestHandler {
    public let closure: HTTPRequestHandlerClosure
    public init(closure: @escaping HTTPRequestHandlerClosure) {
        self.closure = closure
    }
    public func route(context: inout HTTPContext) async throws {
        try await closure(&context)
    }
}
public struct HTTPRequestHandlerRouterClosureWrapper : HTTPRequestHandler {
    public let closure: HTTPRequestHandlerRouterClosure
    public init(closure: @escaping HTTPRequestHandlerRouterClosure) {
        self.closure = closure
    }
    public func route(context: inout HTTPContext) async throws {
        let response = try await closure(context.request)
        context.response.status = response.status
        context.response.body = response.body
        context.response.headers.add(contentsOf: response.headers)
        if let _ = context.response.trailers {
            context.response.trailers?.add(contentsOf: response.trailers ?? [:])
        }
    }
}
public struct HTTPRequestHandlerDataRouteClosureWrapper: HTTPRequestHandler {
    public let closure: HTTPRequestHandlerDataRouteClosure
    public init(closure: @escaping HTTPRequestHandlerDataRouteClosure) {
        self.closure = closure
    }
    public func route(context: inout HTTPContext) async throws {
        let data = try await closure(context.request)
        context.response = data.http()
    }
}
public struct HTTPMiddlewareClosureWrapper : HTTPMiddleware {
    public let closure: HTTPMiddlewareClosure
    public init(closure: @escaping HTTPMiddlewareClosure) {
        self.closure = closure
    }
    public func route(context: inout HTTPContext) async throws -> Bool {
        return try await closure(&context)
    }
}
public struct DefaultHTTPRequestHandler : HTTPRequestHandler {
    public var maps : [HTTPMethod.RawValue: [[String]: HTTPRequestHandler]] = [:]
    public var matches: [HTTPMethod.RawValue: [([String], HTTPRequestHandler)]] = [:]
    public var middlewares: [any HTTPMiddleware] = []
    public var notFound: HTTPRequestHandler?
    public func route(context: inout HTTPContext) async throws {
        for middleware in middlewares {
            if !(try await middleware.route(context: &context)) {
                return
            }
        }
        let path = context.request.url.pathComponents.map { $0.lowercased() }
        if let methodMatches = matches[context.request.method.rawValue] {
            for methodMatch in methodMatches {
                let (methodPath, handler) = methodMatch
                if path.starts(with: methodPath) {
                    try await handler.route(context: &context)
                    return
                }
            }
        }
        if let handler = maps[context.request.method.rawValue]?[path] {
            try await handler.route(context: &context)
        } else {
            if let notFound {
                try await notFound.route(context: &context)
                context.response.status = .notFound
            } else {
                context.response.status = .notFound
            }
        }
    }
    mutating func ensureMethodMap(method: HTTPMethod) {
        guard let _ = maps[method.rawValue] else {
            maps[method.rawValue] = [:]
            return
        }
    }
    mutating func ensureMatchMethodMap(method: HTTPMethod) {
        guard let _ = matches[method.rawValue] else {
            matches[method.rawValue] = []
            return
        }
    }
    mutating func middleware(_ middleware: any HTTPMiddleware) {
        self.middlewares.append(middleware)
    }
    mutating func method(method: HTTPMethod, path: [String], route: HTTPRequestHandler) {
        var targetPath = path
        if targetPath.isEmpty {
            targetPath.append("/")
        }
        if targetPath[0] != "/" {
            targetPath.insert("/", at: 0)
        }
        ensureMethodMap(method: method)
        maps[method.rawValue]?[targetPath.map { $0.lowercased() }] = route
    }
    mutating func method(method: HTTPMethod, path: [String], route: @escaping HTTPRequestHandlerClosure) {
        self.method(method: method, path: path, route: HTTPRequestHandlerClosureWrapper(closure: route))
    }
    mutating func method(method: HTTPMethod, path: [String], route: @escaping HTTPRequestHandlerRouterClosure) {
        self.method(method: method, path: path, route: HTTPRequestHandlerRouterClosureWrapper(closure: route))
    }
    mutating func method(method: HTTPMethod, path: [String], route: @escaping HTTPRequestHandlerDataRouteClosure) {
        self.method(
            method: method,
            path: path,
            route: HTTPRequestHandlerDataRouteClosureWrapper(closure: route)
        )
    }
    mutating func matchMethod(method: HTTPMethod, path: [String], route: HTTPRequestHandler) {
        var targetPath = path
        if targetPath.isEmpty {
            targetPath.append("/")
        }
        if targetPath[0] != "/" {
            targetPath.insert("/", at: 0)
        }
        ensureMatchMethodMap(method: method)
        matches[method.rawValue]?.append((targetPath.map { $0.lowercased() }, route))
    }
    mutating func matchMethod(method: HTTPMethod, path: [String], route: @escaping HTTPRequestHandlerClosure) {
        self.matchMethod(method: method, path: path, route: HTTPRequestHandlerClosureWrapper(closure: route))
    }
    mutating func matchMethod(method: HTTPMethod, path: [String], route: @escaping HTTPRequestHandlerRouterClosure) {
        self.matchMethod(method: method, path: path, route: HTTPRequestHandlerRouterClosureWrapper(closure: route))
    }
    mutating func matchMethod(method: HTTPMethod, path: [String], route: @escaping HTTPRequestHandlerDataRouteClosure) {
        self.matchMethod(
            method: method,
            path: path,
            route: HTTPRequestHandlerDataRouteClosureWrapper(closure: route)
        )
    }
    mutating func notFound(_ route: HTTPRequestHandler) {
        self.notFound = route
    }
    mutating func notFound(_ route: @escaping HTTPRequestHandlerClosure) {
        self.notFound = HTTPRequestHandlerClosureWrapper(closure: route)
    }
    mutating func notFound(_ route: @escaping HTTPRequestHandlerRouterClosure) {
        self.notFound = HTTPRequestHandlerRouterClosureWrapper(closure: route)
    }
    mutating func notFound(_ route: @escaping HTTPRequestHandlerDataRouteClosure) {
        self.notFound = HTTPRequestHandlerDataRouteClosureWrapper(closure: route)
    }
}
public struct HTTPApplication<RequestHandler: HTTPRequestHandler>: Sendable {
    public var handler: RequestHandler
    public init(handler: RequestHandler) {
        self.handler = handler
    }
}
extension HTTPApplication where RequestHandler == DefaultHTTPRequestHandler {
    public init() {
        self.init(handler: DefaultHTTPRequestHandler())
    }
    public mutating func middleware(_ middleware: HTTPMiddleware) {
        handler.middleware(middleware)
    }
    public mutating func middleware(_ middleware: @escaping HTTPMiddlewareClosure) {
        handler.middleware(HTTPMiddlewareClosureWrapper(closure: middleware))
    }
    public mutating func notFound(_ route: HTTPRequestHandler) {
        handler.notFound(route)
    }
    public mutating func notFound(_ route: @escaping HTTPRequestHandlerClosure) {
        handler.notFound(HTTPRequestHandlerClosureWrapper(closure: route))
    }
    public mutating func notFound(_ route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.notFound(HTTPRequestHandlerRouterClosureWrapper(closure: route))
    }
    public mutating func notFound(_ route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.notFound(HTTPRequestHandlerDataRouteClosureWrapper(closure: route))
    }
    public mutating func method(method: HTTPMethod, _ path: String..., route: HTTPRequestHandler) {
        handler.method(method: method, path: path, route: route)
    }
    public mutating func matchMethod(method: HTTPMethod, _ path: String..., route: HTTPRequestHandler) {
        handler.matchMethod(method: method, path: path, route: route)
    }
    public mutating func get(_ path: String..., route: HTTPRequestHandler) {
        handler.method(method: .GET, path: path, route: route)
    }
    public mutating func get(_ path: String..., route: @escaping HTTPRequestHandlerClosure) {
        handler.method(method: .GET, path: path, route: route)
    }
    public mutating func get(_ path: String..., route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.method(method: .GET, path: path, route: route)
    }
    public mutating func get(_ path: String..., route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.method(method: .GET, path: path, route: route)
    }
    public mutating func post(_ path: String..., route: HTTPRequestHandler) {
        handler.method(method: .POST, path: path, route: route)
    }
    public mutating func post(_ path: String..., route: @escaping HTTPRequestHandlerClosure) {
        handler.method(method: .POST, path: path, route: route)
    }
    public mutating func post(_ path: String..., route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.method(method: .POST, path: path, route: route)
    }
    public mutating func post(_ path: String..., route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.method(method: .POST, path: path, route: route)
    }
    public mutating func put(_ path: String..., route: HTTPRequestHandler) {
        handler.method(method: .PUT, path: path, route: route)
    }
    public mutating func put(_ path: String..., route: @escaping HTTPRequestHandlerClosure) {
        handler.method(method: .PUT, path: path, route: route)
    }
    public mutating func put(_ path: String..., route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.method(method: .PUT, path: path, route: route)
    }
    public mutating func put(_ path: String..., route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.method(method: .PUT, path: path, route: route)
    }
    public mutating func delete(_ path: String..., route: HTTPRequestHandler) {
        handler.method(method: .DELETE, path: path, route: route)
    }
    public mutating func delete(_ path: String..., route: @escaping HTTPRequestHandlerClosure) {
        handler.method(method: .DELETE, path: path, route: route)
    }
    public mutating func delete(_ path: String..., route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.method(method: .DELETE, path: path, route: route)
    }
    public mutating func delete(_ path: String..., route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.method(method: .DELETE, path: path, route: route)
    }
    public mutating func matchGet(_ path: String..., route: HTTPRequestHandler) {
        handler.matchMethod(method: .GET, path: path, route: route)
    }
    public mutating func matchGet(_ path: String..., route: @escaping HTTPRequestHandlerClosure) {
        handler.matchMethod(method: .GET, path: path, route: route)
    }
    public mutating func matchGet(_ path: String..., route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.matchMethod(method: .GET, path: path, route: route)
    }
    public mutating func matchGet(_ path: String..., route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.matchMethod(method: .GET, path: path, route: route)
    }
    public mutating func matchPost(_ path: String..., route: HTTPRequestHandler) {
        handler.matchMethod(method: .POST, path: path, route: route)
    }
    public mutating func matchPost(_ path: String..., route: @escaping HTTPRequestHandlerClosure) {
        handler.matchMethod(method: .POST, path: path, route: route)
    }
    public mutating func matchPost(_ path: String..., route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.matchMethod(method: .POST, path: path, route: route)
    }
    public mutating func matchPost(_ path: String..., route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.matchMethod(method: .POST, path: path, route: route)
    }
    public mutating func matchPut(_ path: String..., route: HTTPRequestHandler) {
        handler.matchMethod(method: .PUT, path: path, route: route)
    }
    public mutating func matchPut(_ path: String..., route: @escaping HTTPRequestHandlerClosure) {
        handler.matchMethod(method: .PUT, path: path, route: route)
    }
    public mutating func matchPut(_ path: String..., route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.matchMethod(method: .PUT, path: path, route: route)
    }
    public mutating func matchPut(_ path: String..., route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.matchMethod(method: .PUT, path: path, route: route)
    }
    public mutating func matchDelete(_ path: String..., route: HTTPRequestHandler) {
        handler.matchMethod(method: .DELETE, path: path, route: route)
    }
    public mutating func matchDelete(_ path: String..., route: @escaping HTTPRequestHandlerClosure) {
        handler.matchMethod(method: .DELETE, path: path, route: route)
    }
    public mutating func matchDelete(_ path: String..., route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.matchMethod(method: .DELETE, path: path, route: route)
    }
    public mutating func matchDelete(_ path: String..., route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.matchMethod(method: .DELETE, path: path, route: route)
    }
}
