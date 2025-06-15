//
//  Operators.swift
//  Harbeth
//
//  Created by Condy on 2022/2/13.
//
//  This file has been refactored to replace custom operators
//  with named asynchronous functions for better clarity and Swift Concurrency compatibility.

import Foundation
import CoreVideo
import MetalKit

// MARK: - Single Filter Application

@discardableResult @inlinable
public func applyFilter(_ filter: C7FilterProtocol, to element: MTLTexture) async -> MTLTexture {
    return await HarbethIO(element: element, filter: filter).filtered()
}

@discardableResult @inlinable
public func applyFilter(_ filter: C7FilterProtocol, to element: C7Image) async -> C7Image {
    return await HarbethIO(element: element, filter: filter).filtered()
}

@discardableResult @inlinable
public func applyFilter(_ filter: C7FilterProtocol, to element: CGImage) async -> CGImage {
    return await HarbethIO(element: element, filter: filter).filtered()
}

@discardableResult @inlinable
public func applyFilter(_ filter: C7FilterProtocol, to element: CIImage) async -> CIImage {
    return await HarbethIO(element: element, filter: filter).filtered()
}

@discardableResult @inlinable
public func applyFilter(_ filter: C7FilterProtocol, to element: CMSampleBuffer) async -> CMSampleBuffer {
    return await HarbethIO(element: element, filter: filter).filtered()
}

@discardableResult @inlinable
public func applyFilter(_ filter: C7FilterProtocol, to element: CVPixelBuffer) async -> CVPixelBuffer {
    return await HarbethIO(element: element, filter: filter).filtered()
}

// MARK: - Multiple Filters Application

@discardableResult @inlinable
public func applyFilters(_ filters: [C7FilterProtocol], to element: MTLTexture) async -> MTLTexture {
    return await HarbethIO(element: element, filters: filters).filtered()
}

@discardableResult @inlinable
public func applyFilters(_ filters: [C7FilterProtocol], to element: C7Image) async -> C7Image {
    return await HarbethIO(element: element, filters: filters).filtered()
}

@discardableResult @inlinable
public func applyFilters(_ filters: [C7FilterProtocol], to element: CGImage) async -> CGImage {
    return await HarbethIO(element: element, filters: filters).filtered()
}

@discardableResult @inlinable
public func applyFilters(_ filters: [C7FilterProtocol], to element: CIImage) async -> CIImage {
    return await HarbethIO(element: element, filters: filters).filtered()
}

@discardableResult @inlinable
public func applyFilters(_ filters: [C7FilterProtocol], to element: CMSampleBuffer) async -> CMSampleBuffer {
    return await HarbethIO(element: element, filters: filters).filtered()
}

@discardableResult @inlinable
public func applyFilters(_ filters: [C7FilterProtocol], to element: CVPixelBuffer) async -> CVPixelBuffer {
    return await HarbethIO(element: element, filters: filters).filtered()
}
