//
//  Destype.swift
//  Harbeth
//
//  Created by Condy on 2022/10/22.
//

import Foundation

public protocol Destype {
    
    associatedtype Element
    
    var element: Element { get }
    
    var filters: [C7FilterProtocol] { get }
    
    init(element: Element, filter: C7FilterProtocol)
    
    init(element: Element, filters: C7FilterProtocol...)
    
    init(element: Element, filters: [C7FilterProtocol])
    
    /// Add filters to sources asynchronously.
    /// - Returns: Added filter source.
    func output() async throws -> Element
    
    /// Asynchronous quickly add filters to sources.
    /// This method is now largely identical to `output()` in its async throws signature.
    /// Implementers can choose to provide a distinct implementation or have it call `output()`.
    func transmitOutput() async throws -> Element
}

extension Destype {
    
    public init(element: Element, filter: C7FilterProtocol) {
        self.init(element: element, filters: [filter])
    }
    
    public init(element: Element, filters: C7FilterProtocol...) {
        self.init(element: element, filters: filters)
    }
    
    /// Add filters to sources asynchronously.
    /// If itails, it returns element.
    public func filtered() async -> Element {
        do {
            return try await self.output()
        } catch {
            return element
        }
    }
    
    /// Asynchronous quickly add filters to sources.
    /// This default implementation calls the new `async throws transmitOutput()` protocol requirement.
    @available(*, deprecated, message: "Use `async throws output()` or `async throws transmitOutput()` directly and handle errors with try-catch.", renamed: "output")
    public func transmitOutput(success: @escaping (Element) -> Void, failed: ((HarbethError) -> Void)? = nil) async {
        do {
            // Since the protocol `transmitOutput()` is now async throws, we call that.
            // Or, if it's intended that this convenience method should always reflect `output()`'s behavior:
            let result = try await self.output() // Changed to output() for consistency as per HarbethIO refactor
            success(result)
        } catch {
            failed?(error as? HarbethError ?? .unknown)
        }
    }
}
