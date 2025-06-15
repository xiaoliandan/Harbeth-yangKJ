//
//  MTLSize+Ext.swift
//  Harbeth
//
//  Created by Condy on 2023/8/8.
//

import Foundation
@preconcurrency import MetalKit

extension MTLSize: HarbethCompatible { }

extension HarbethWrapper where MTLSize == Base {
    
    /// Maximum metal texture size that can be processed.
    /// - Parameter device: Device information to create other objects.
    /// - Returns: New metal texture size.
    @MainActor public func maxTextureSize(device: MTLDevice? = nil) async -> MTLSize {
        let effectiveDevice: MTLDevice
        if let providedDevice = device {
            effectiveDevice = providedDevice
        } else {
            effectiveDevice = await Device.device()
        }

        var supportsOnly8KValue: Bool
        #if targetEnvironment(macCatalyst)
        supportsOnly8KValue = !effectiveDevice.supportsFamily(.apple3)
        #elseif os(macOS)
        supportsOnly8KValue = false
        #else
        if #available(iOS 13.0, *) {
            supportsOnly8KValue = !effectiveDevice.supportsFamily(.apple3)
        } else if #available(iOS 11.0, *)  {
            supportsOnly8KValue = !effectiveDevice.supportsFeatureSet(.iOS_GPUFamily3_v3)
        } else {
            supportsOnly8KValue = false
        }
        #endif
        let maxSide: Int = supportsOnly8KValue ? 8192 : 16_384

        guard base.width > 0, base.height > 0 else {
            return .init(width: 0, height: 0, depth: base.depth) // Using base.depth
        }
        let aspectRatio = Float(base.width) / Float(base.height)
        if aspectRatio > 1 {
            let resultWidth = min(base.width, maxSide)
            let resultHeight = Float(resultWidth) / aspectRatio
            return MTLSize(width: resultWidth, height: Int(resultHeight.rounded()), depth: base.depth)
        } else {
            let resultHeight = min(base.height, maxSide)
            let resultWidth = Float(resultHeight) * aspectRatio
            return MTLSize(width: Int(resultWidth.rounded()), height: resultHeight, depth: base.depth)
        }
    }
}
