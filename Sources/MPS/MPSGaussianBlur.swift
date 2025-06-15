//
//  MPSGaussianBlur.swift
//  Harbeth
//
//  Created by Condy on 2022/10/14.
//

import Foundation
import MetalPerformanceShaders

// Note: @unchecked Sendable is used because this struct holds non-Sendable MPSImageGaussianBlur. Ensure thread-safe usage.
public struct MPSGaussianBlur: MPSKernelProtocol, @unchecked Sendable {
    
    private let metalDevice: MTLDevice
    public static let range: ParameterRange<Float, MPSGaussianBlur> = .init(min: 0, max: 100, value: 10)
    
    /// The radius determines how many pixels are used to create the blur.
    @Clamping(MPSGaussianBlur.range.min...MPSGaussianBlur.range.max) public var radius: Float = MPSGaussianBlur.range.value {
        didSet {
            self.gaussian = MPSImageGaussianBlur(device: self.metalDevice, sigma: ceil(radius))
        }
    }
    
    public var modifier: Modifier {
        return .mps(performance: self.gaussian)
    }
    
    public func encode(commandBuffer: MTLCommandBuffer, textures: [MTLTexture]) async throws -> MTLTexture {
        let destinationTexture = textures[0]
        let sourceTexture = textures[1]
        self.gaussian.encode(commandBuffer: commandBuffer, sourceTexture: sourceTexture, destinationTexture: destinationTexture)
        return destinationTexture
    }
    
    private var gaussian: MPSImageGaussianBlur {
        didSet {
            gaussian.edgeMode = .clamp
        }
    }
    
    public init(radius: Float = MPSGaussianBlur.range.value) async {
        self.metalDevice = await Device.device()
        self.gaussian = MPSImageGaussianBlur(device: self.metalDevice, sigma: ceil(radius))
        self.gaussian.edgeMode = .clamp // Ensure edgeMode is set in init
    }
}
