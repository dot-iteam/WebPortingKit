//
//  Context.swift
//  WebPortingKit
//
//  Created by Dot iTeam on 2026-06-12.
//

import Foundation

/// Per-request storage for middleware, routes, and dependency-style values.
///
/// `RequestContext` is attached to each ``HTTPRequest``. It is an actor so values
/// can be shared safely between asynchronous middleware and route handlers. Values
/// can be keyed either by an explicit key path or by their concrete type.
public actor RequestContext {
    private var store: [AnyHashable: any Sendable] = [:]

    /// Creates an empty request context.
    public init() {}

    /// Stores `value` under a key-path identity.
    ///
    /// Use this form when multiple values may have the same Swift type but distinct
    /// semantic meanings.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - keyPath: The key-path identity used as the storage key.
    public func set<Root, Value: Sendable>(_ value: Value, for keyPath: KeyPath<Root, Value>) {
        store[keyPath] = value
    }

    /// Returns the value stored for `keyPath`, if present and of the expected type.
    ///
    /// - Parameter keyPath: The key-path identity used as the storage key.
    public func get<Root, Value: Sendable>(_ keyPath: KeyPath<Root, Value>) -> Value? {
        store[keyPath] as? Value
    }

    /// Removes the value stored for `keyPath`.
    ///
    /// - Parameter keyPath: The key-path identity used as the storage key.
    public func remove<Root, Value: Sendable>(_ keyPath: KeyPath<Root, Value>) {
        store[keyPath] = nil
    }

    /// Stores `value` under its concrete Swift type.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - type: The type identity used as the storage key. Defaults to `Value.self`.
    public func set<Value: Sendable>(_ value: Value, as type: Value.Type = Value.self) {
        store[ObjectIdentifier(type)] = value
    }

    /// Returns the value stored for `type`, if present.
    ///
    /// - Parameter type: The type identity used as the storage key.
    public func get<Value: Sendable>(_ type: Value.Type) -> Value? {
        store[ObjectIdentifier(Value.self)] as? Value
    }

    /// Removes the value stored for `type`.
    ///
    /// - Parameter type: The type identity used as the storage key.
    public func remove<Value: Sendable>(_ type: Value.Type) {
        store[ObjectIdentifier(Value.self)] = nil
    }
}
