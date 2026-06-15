//
//  HTTPApplication.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-05-29.
//

import NIOHTTP1
import Foundation
/// Closure route handler that mutates an ``HTTPContext`` in place.
public typealias HTTPRequestHandlerClosure = @Sendable (inout HTTPContext) async throws -> ()

/// Closure route handler that returns a complete ``HTTPResponse`` for a request.
public typealias HTTPRequestHandlerRouterClosure = @Sendable (HTTPRequest) async throws -> HTTPResponse

/// Closure route handler that returns response bytes for a request.
public typealias HTTPRequestHandlerDataRouteClosure = @Sendable (HTTPRequest) async throws -> Data

/// Closure middleware that can continue, respond, or drop a request.
public typealias HTTPMiddlewareClosure = @Sendable (inout HTTPContext) async throws -> HTTPMiddlewareDecision

extension Data {
    /// Wraps data in a `200 OK` response with a `Content-Type` header.
    public func http(type: String = "application/octet-stream") -> HTTPResponse {
        return HTTPResponse(status: .ok, headers: HTTPHeaders([("content-type", type)]), body: tryGetByteBuffer(
            data: self))
    }
}
/// A route handler that mutates an HTTP context.
public protocol HTTPRequestHandler: Sendable {
    /// Handles a request by reading and mutating `context`.
    func route(context: inout HTTPContext) async throws
}

/// Routing result returned by a routing handler.
public enum HTTPRoutingDecision: Sendable {
    /// Send the response currently stored in the context.
    case respond

    /// Close the connection without sending a response.
    case drop
}

/// A request router that decides how a completed request should finish.
public protocol HTTPRoutingHandler: Sendable {
    /// Routes the request in `context` and returns the final routing decision.
    func routeWithDecision(context: inout HTTPContext) async throws -> HTTPRoutingDecision
}

/// Middleware routing decision.
public enum HTTPMiddlewareDecision: Sendable {
    /// Continue to the next middleware or route handler.
    case next

    /// Stop routing and send the response currently stored in the context.
    case respond

    /// Stop routing and close the connection without sending a response.
    case drop
}

/// Middleware that can inspect and mutate a request context before a route runs.
public protocol HTTPMiddleware : Sendable {
    /// Processes `context` and chooses how routing continues.
    func route(context: inout HTTPContext) async throws -> HTTPMiddlewareDecision
}

/// Provides request-body limits for route lookup.
public protocol HTTPBodyLimitProviding: Sendable {
    /// Returns a maximum body size for `head`, or `nil` to use the server default.
    func maximumBodySize(for head: HTTPRequestHead) -> Int?
}
/// Adapts an ``HTTPRequestHandlerClosure`` to ``HTTPRequestHandler``.
public struct HTTPRequestHandlerClosureWrapper : HTTPRequestHandler {
    /// The wrapped route closure.
    public let closure: HTTPRequestHandlerClosure

    /// Creates a wrapper around `closure`.
    public init(closure: @escaping HTTPRequestHandlerClosure) {
        self.closure = closure
    }

    /// Invokes the wrapped closure.
    public func route(context: inout HTTPContext) async throws {
        try await closure(&context)
    }
}
/// Adapts an ``HTTPRequestHandlerRouterClosure`` to ``HTTPRequestHandler``.
public struct HTTPRequestHandlerRouterClosureWrapper : HTTPRequestHandler {
    /// The wrapped response-producing route closure.
    public let closure: HTTPRequestHandlerRouterClosure

    /// Creates a wrapper around `closure`.
    public init(closure: @escaping HTTPRequestHandlerRouterClosure) {
        self.closure = closure
    }

    /// Invokes the wrapped closure and merges its response into `context`.
    public func route(context: inout HTTPContext) async throws {
        let response = try await closure(context.request)
        context.response.status = response.status
        context.response.body = response.body
        context.response.headers.add(contentsOf: response.headers)
        if let trailers = response.trailers
        {
            if context.response.trailers == nil {
                context.response.trailers = [:]
            }
            context.response.trailers?.add(contentsOf: trailers)
        }
    }
}
/// Adapts an ``HTTPRequestHandlerDataRouteClosure`` to ``HTTPRequestHandler``.
public struct HTTPRequestHandlerDataRouteClosureWrapper: HTTPRequestHandler {
    /// The wrapped data-producing route closure.
    public let closure: HTTPRequestHandlerDataRouteClosure

    /// Creates a wrapper around `closure`.
    public init(closure: @escaping HTTPRequestHandlerDataRouteClosure) {
        self.closure = closure
    }

    /// Invokes the wrapped closure and stores its bytes as the response body.
    public func route(context: inout HTTPContext) async throws {
        let data = try await closure(context.request)
        context.response = data.http()
    }
}
/// Adapts an ``HTTPMiddlewareClosure`` to ``HTTPMiddleware``.
public struct HTTPMiddlewareClosureWrapper : HTTPMiddleware {
    /// The wrapped middleware closure.
    public let closure: HTTPMiddlewareClosure

    /// Creates a wrapper around `closure`.
    public init(closure: @escaping HTTPMiddlewareClosure) {
        self.closure = closure
    }

    /// Invokes the wrapped middleware closure.
    public func route(context: inout HTTPContext) async throws -> HTTPMiddlewareDecision {
        return try await closure(&context)
    }
}
/// Default path-based router used by ``HTTPApplication``.
public struct DefaultHTTPRoutingHandler : HTTPRoutingHandler, HTTPBodyLimitProviding {
    /// A registered route and its optional body-size override.
    public struct Route: Sendable {
        /// Handler invoked for the route.
        public let handler: any HTTPRequestHandler

        /// Optional maximum request body size for this route.
        public let maximumBodySize: Int?

        /// Creates a route from a handler and optional body-size limit.
        public init(handler: any HTTPRequestHandler, maximumBodySize: Int? = nil) {
            self.handler = handler
            self.maximumBodySize = maximumBodySize
        }
    }

    /// Exact routes keyed by method raw value and normalized path components.
    public var maps : [HTTPMethod.RawValue: [[String]: Route]] = [:]

    /// Prefix routes keyed by method raw value.
    public var matches: [HTTPMethod.RawValue: [([String], Route)]] = [:]

    /// Middleware run before matched routes and the not-found handler.
    public var middlewares: [any HTTPMiddleware] = []

    /// Optional handler used for unmatched requests.
    public var notFound: HTTPRequestHandler?

    /// Application-wide maximum request body size.
    public var maximumBodySize: Int? = nil

    /// Creates a default router.
    public init(maximumBodySize: Int? = nil) {
        self.maximumBodySize = maximumBodySize
    }

    /// Routes a request through middleware, exact/prefix routes, and not-found handling.
    public func routeWithDecision(context: inout HTTPContext) async throws -> HTTPRoutingDecision {
        let path = context.request.normalizedPath
        if let route = getRoute(method: context.request.method, path: path) {
            if let maximumBodySize = maximumBodySize(for: route), let body = context.request.body, body.readableBytes > maximumBodySize {
                context.response.status = .payloadTooLarge
                context.response.headers.replaceOrAdd(name: "content-length", value: "0")
                return .respond
            }
            for middleware in middlewares {
                switch try await middleware.route(context: &context) {
                case .next:
                    continue
                case .respond:
                    return .respond
                case .drop:
                    return .drop
                }
            }
            try await route.handler.route(context: &context)
            return .respond
        } else {
            for middleware in middlewares {
                switch try await middleware.route(context: &context) {
                case .next:
                    continue
                case .respond:
                    return .respond
                case .drop:
                    return .drop
                }
            }
            if let notFound {
                try await notFound.route(context: &context)
                context.response.status = .notFound
            } else {
                context.response.status = .notFound
            }
            return .respond
        }
    }
    /// Returns the effective body-size limit for the route addressed by `head`.
    public func maximumBodySize(for head: HTTPRequestHead) -> Int? {
        let path = (URL(string: head.uri) ?? URL(fileURLWithPath: "/")).pathComponents.normalizedPath
        guard let route = getRoute(method: head.method, path: path) else {
            return nil
        }
        return maximumBodySize(for: route)
    }
    /// Combines the application and route body-size limits for `route`.
    public func maximumBodySize(for route: Route) -> Int? {
        let routeMaximumBodySize = route.maximumBodySize
        switch (maximumBodySize, routeMaximumBodySize) {
        case let (app?, route?):
            return min(app, route)
        case let (app?, nil):
            return app
        case let (nil, route?):
            return route
        case (nil, nil):
            return nil
        }
    }
    private func getRoute(method: HTTPMethod, path: [String]) -> Route? {
        if let route = maps[method.rawValue]?[path] {
            return route
        }
        if let methodMatches = matches[method.rawValue] {
            for methodMatch in methodMatches {
                let (methodPath, route) = methodMatch
                if path.starts(with: methodPath) {
                    return route
                }
            }
        }
        return nil
    }
    /// Registers middleware that runs before matched routes and the not-found handler.
    ///
    /// Middleware runs in registration order. Returning `.respond` stops routing and
    /// sends the current response; returning `.drop` closes the connection.
    public mutating func middleware(_ middleware: any HTTPMiddleware) {
        self.middlewares.append(middleware)
    }

    /// Registers an exact route for `method` and `path` using a handler value.
    ///
    /// Empty paths are normalized to `/`, and paths missing a leading `/` receive one.
    /// Matching is case-insensitive because path components are lowercased before
    /// storage.
    public mutating func method(method: HTTPMethod, path: [String], maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        var targetPath = path
        if targetPath.isEmpty {
            targetPath.append("/")
        }
        if targetPath[0] != "/" {
            targetPath.insert("/", at: 0)
        }
        maps[method.rawValue, default: [:]][targetPath.normalizedPath] = Route(handler: route, maximumBodySize: maximumBodySize)
    }
    /// Registers an exact route using a context-mutating closure.
    public mutating func method(method: HTTPMethod, path: [String], maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        self.method(method: method, path: path, maximumBodySize: maximumBodySize, route: HTTPRequestHandlerClosureWrapper(closure: route))
    }

    /// Registers an exact route using a response-returning closure.
    public mutating func method(method: HTTPMethod, path: [String], maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        self.method(method: method, path: path, maximumBodySize: maximumBodySize, route: HTTPRequestHandlerRouterClosureWrapper(closure: route))
    }

    /// Registers an exact route using a data-returning closure.
    public mutating func method(method: HTTPMethod, path: [String], maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        self.method(
            method: method,
            path: path,
            maximumBodySize: maximumBodySize,
            route: HTTPRequestHandlerDataRouteClosureWrapper(closure: route)
        )
    }
    /// Registers a prefix route for `method` and `path` using a handler value.
    ///
    /// A prefix route handles requests whose normalized path starts with `path`.
    /// Exact routes registered with `method` take precedence over prefix routes.
    public mutating func matchMethod(method: HTTPMethod, path: [String], maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        var targetPath = path
        if targetPath.isEmpty {
            targetPath.append("/")
        }
        if targetPath[0] != "/" {
            targetPath.insert("/", at: 0)
        }
        matches[method.rawValue, default: []].append((targetPath.map { $0.lowercased() }, Route(handler: route, maximumBodySize: maximumBodySize)))
    }
    /// Registers a prefix route using a context-mutating closure.
    public mutating func matchMethod(method: HTTPMethod, path: [String], maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        self.matchMethod(method: method, path: path, maximumBodySize: maximumBodySize, route: HTTPRequestHandlerClosureWrapper(closure: route))
    }

    /// Registers a prefix route using a response-returning closure.
    public mutating func matchMethod(method: HTTPMethod, path: [String], maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        self.matchMethod(method: method, path: path, maximumBodySize: maximumBodySize, route: HTTPRequestHandlerRouterClosureWrapper(closure: route))
    }

    /// Registers a prefix route using a data-returning closure.
    public mutating func matchMethod(method: HTTPMethod, path: [String], maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        self.matchMethod(
            method: method,
            path: path,
            maximumBodySize: maximumBodySize,
            route: HTTPRequestHandlerDataRouteClosureWrapper(closure: route)
        )
    }
    /// Registers a prefix `GET` route that serves files from a URL root.
    public mutating func staticFiles(
        path: [String],
        location: URL,
        mimeTypes: HTTPMimeTypeRegistry = .default,
        defaultMimeType: String = "application/octet-stream",
        cacheControl: String? = "public, max-age=0, must-revalidate"
    ) {
        self.matchMethod(method: .GET, path: path) { request in
            await staticFile(
                request: request,
                from: location,
                pathPrefix: path,
                mimeTypes: mimeTypes,
                defaultMimeType: defaultMimeType,
                cacheControl: cacheControl
            )
        }
    }
    /// Registers a prefix `GET` route that serves files from a filesystem path.
    public mutating func staticFiles(
        path: [String],
        location: String,
        mimeTypes: HTTPMimeTypeRegistry = .default,
        defaultMimeType: String = "application/octet-stream",
        cacheControl: String? = "public, max-age=0, must-revalidate"
    ) {
        self.staticFiles(
            path: path,
            location: URL(fileURLWithPath: location),
            mimeTypes: mimeTypes,
            defaultMimeType: defaultMimeType,
            cacheControl: cacheControl
        )
    }
    /// Registers a handler for unmatched requests.
    ///
    /// The router forces the final response status to `404 Not Found` after this
    /// handler runs, while preserving any response headers and body it sets.
    public mutating func notFound(_ route: HTTPRequestHandler) {
        self.notFound = route
    }

    /// Registers a context-mutating closure for unmatched requests.
    public mutating func notFound(_ route: @escaping HTTPRequestHandlerClosure) {
        self.notFound = HTTPRequestHandlerClosureWrapper(closure: route)
    }

    /// Registers a response-returning closure for unmatched requests.
    public mutating func notFound(_ route: @escaping HTTPRequestHandlerRouterClosure) {
        self.notFound = HTTPRequestHandlerRouterClosureWrapper(closure: route)
    }

    /// Registers a data-returning closure for unmatched requests.
    public mutating func notFound(_ route: @escaping HTTPRequestHandlerDataRouteClosure) {
        self.notFound = HTTPRequestHandlerDataRouteClosureWrapper(closure: route)
    }
}
/// A web application with a routing handler.
public struct HTTPApplication<RoutingHandler: HTTPRoutingHandler>: Sendable {
    /// The routing handler used to process requests.
    public var handler: RoutingHandler

    /// Creates an application with a custom routing handler.
    public init(handler: RoutingHandler) {
        self.handler = handler
    }
}

extension HTTPApplication where RoutingHandler == DefaultHTTPRoutingHandler {
    /// Creates an application using ``DefaultHTTPRoutingHandler``.
    public init() {
        self.init(handler: DefaultHTTPRoutingHandler())
    }

    /// Registers middleware that runs before route handlers.
    public mutating func middleware(_ middleware: HTTPMiddleware) {
        handler.middleware(middleware)
    }

    /// Registers closure middleware that runs before route handlers.
    public mutating func middleware(_ middleware: @escaping HTTPMiddlewareClosure) {
        handler.middleware(HTTPMiddlewareClosureWrapper(closure: middleware))
    }

    /// Registers a handler for unmatched requests.
    public mutating func notFound(_ route: HTTPRequestHandler) {
        handler.notFound(route)
    }

    /// Registers a context-mutating closure for unmatched requests.
    public mutating func notFound(_ route: @escaping HTTPRequestHandlerClosure) {
        handler.notFound(HTTPRequestHandlerClosureWrapper(closure: route))
    }

    /// Registers a response-returning closure for unmatched requests.
    public mutating func notFound(_ route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.notFound(HTTPRequestHandlerRouterClosureWrapper(closure: route))
    }

    /// Registers a data-returning closure for unmatched requests.
    public mutating func notFound(_ route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.notFound(HTTPRequestHandlerDataRouteClosureWrapper(closure: route))
    }

    /// Registers an exact route for `method` and `path`.
    public mutating func method(method: HTTPMethod, _ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.method(method: method, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix route for `method` and `path`.
    public mutating func matchMethod(method: HTTPMethod, _ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.matchMethod(method: method, path: path, maximumBodySize: maximumBodySize, route: route)
    }
    /// Registers an exact `GET` route using a handler value.
    public mutating func get(_ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.method(method: .GET, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `GET` route using a context-mutating closure.
    public mutating func get(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        handler.method(method: .GET, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `GET` route using a response-returning closure.
    public mutating func get(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.method(method: .GET, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `GET` route using a data-returning closure.
    public mutating func get(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.method(method: .GET, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `POST` route using a handler value.
    public mutating func post(_ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.method(method: .POST, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `POST` route using a context-mutating closure.
    public mutating func post(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        handler.method(method: .POST, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `POST` route using a response-returning closure.
    public mutating func post(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.method(method: .POST, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `POST` route using a data-returning closure.
    public mutating func post(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.method(method: .POST, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `PUT` route using a handler value.
    public mutating func put(_ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.method(method: .PUT, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `PUT` route using a context-mutating closure.
    public mutating func put(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        handler.method(method: .PUT, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `PUT` route using a response-returning closure.
    public mutating func put(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.method(method: .PUT, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `PUT` route using a data-returning closure.
    public mutating func put(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.method(method: .PUT, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `DELETE` route using a handler value.
    public mutating func delete(_ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.method(method: .DELETE, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `DELETE` route using a context-mutating closure.
    public mutating func delete(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        handler.method(method: .DELETE, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `DELETE` route using a response-returning closure.
    public mutating func delete(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.method(method: .DELETE, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers an exact `DELETE` route using a data-returning closure.
    public mutating func delete(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.method(method: .DELETE, path: path, maximumBodySize: maximumBodySize, route: route)
    }
    /// Registers a prefix `GET` route using a handler value.
    public mutating func matchGet(_ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.matchMethod(method: .GET, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `GET` route using a context-mutating closure.
    public mutating func matchGet(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        handler.matchMethod(method: .GET, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `GET` route using a response-returning closure.
    public mutating func matchGet(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.matchMethod(method: .GET, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `GET` route using a data-returning closure.
    public mutating func matchGet(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.matchMethod(method: .GET, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `GET` route that serves static files from a URL root.
    public mutating func staticFiles(
        _ path: String...,
        location: URL,
        mimeTypes: HTTPMimeTypeRegistry = .default,
        defaultMimeType: String = "application/octet-stream",
        cacheControl: String? = "public, max-age=0, must-revalidate"
    ) {
        handler.staticFiles(path: path, location: location, mimeTypes: mimeTypes, defaultMimeType: defaultMimeType, cacheControl: cacheControl)
    }

    /// Registers a prefix `GET` route that serves static files from a filesystem path.
    public mutating func staticFiles(
        _ path: String...,
        location: String,
        mimeTypes: HTTPMimeTypeRegistry = .default,
        defaultMimeType: String = "application/octet-stream",
        cacheControl: String? = "public, max-age=0, must-revalidate"
    ) {
        handler.staticFiles(path: path, location: location, mimeTypes: mimeTypes, defaultMimeType: defaultMimeType, cacheControl: cacheControl)
    }

    /// Registers a prefix `POST` route using a handler value.
    public mutating func matchPost(_ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.matchMethod(method: .POST, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `POST` route using a context-mutating closure.
    public mutating func matchPost(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        handler.matchMethod(method: .POST, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `POST` route using a response-returning closure.
    public mutating func matchPost(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.matchMethod(method: .POST, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `POST` route using a data-returning closure.
    public mutating func matchPost(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.matchMethod(method: .POST, path: path, maximumBodySize: maximumBodySize, route: route)
    }
    /// Registers a prefix `PUT` route using a handler value.
    public mutating func matchPut(_ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.matchMethod(method: .PUT, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `PUT` route using a context-mutating closure.
    public mutating func matchPut(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        handler.matchMethod(method: .PUT, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `PUT` route using a response-returning closure.
    public mutating func matchPut(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.matchMethod(method: .PUT, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `PUT` route using a data-returning closure.
    public mutating func matchPut(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.matchMethod(method: .PUT, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `DELETE` route using a handler value.
    public mutating func matchDelete(_ path: String..., maximumBodySize: Int? = nil, route: HTTPRequestHandler) {
        handler.matchMethod(method: .DELETE, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `DELETE` route using a context-mutating closure.
    public mutating func matchDelete(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerClosure) {
        handler.matchMethod(method: .DELETE, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `DELETE` route using a response-returning closure.
    public mutating func matchDelete(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerRouterClosure) {
        handler.matchMethod(method: .DELETE, path: path, maximumBodySize: maximumBodySize, route: route)
    }

    /// Registers a prefix `DELETE` route using a data-returning closure.
    public mutating func matchDelete(_ path: String..., maximumBodySize: Int? = nil, route: @escaping HTTPRequestHandlerDataRouteClosure) {
        handler.matchMethod(method: .DELETE, path: path, maximumBodySize: maximumBodySize, route: route)
    }
}
