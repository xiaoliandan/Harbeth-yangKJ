//
//  MPSBoxBlur.swift
//  Harbeth
//
//  Created by Condy on 2024/3/3.
//

import Foundation
@preconcurrency import MetalPerformanceShaders

// Note: @unchecked Sendable is used because this struct holds non-Sendable MPSImageBox. Ensure thread-safe usage.
public struct MPSBoxBlur: MPSKernelProtocol, @unchecked Sendable {
    
    private let metalDevice: MTLDevice
    public static let range: ParameterRange<Float, MPSBoxBlur> = .init(min: 0, max: 100, value: 10)
    
    /// The radius determines how many pixels are used to create the blur.
    @Clamping(MPSBoxBlur.range.min...MPSBoxBlur.range.max) public var radius: Float = MPSBoxBlur.range.value {
        didSet {
            let kernelSize = MPSBoxBlur.roundToOdd(radius)
            self.boxBlur = MPSImageBox(device: self.metalDevice, kernelWidth: kernelSize, kernelHeight: kernelSize)
        }
    }
    
    public var modifier: Modifier {
        return .mps(performance: self.boxBlur)
    }
    
    public func encode(commandBuffer: MTLCommandBuffer, textures: [MTLTexture]) async throws -> MTLTexture {
        let destinationTexture = textures[0]
        let sourceTexture = textures[1]
        self.boxBlur.encode(commandBuffer: commandBuffer, sourceTexture: sourceTexture, destinationTexture: destinationTexture)
        return destinationTexture
    }
    
    private var boxBlur: MPSImageBox
    
    @MainActor public init(radius: Float = MPSBoxBlur.range.value) async {
        self.metalDevice = await Device.device()
        let kernelSize = MPSBoxBlur.roundToOdd(radius)
        self.boxBlur = MPSImageBox(device: self.metalDevice, kernelWidth: kernelSize, kernelHeight: kernelSize)
    }
    
    // MPS box blur kernels need to be odd
    static func roundToOdd(_ number: Float) -> Int {
        return 2 * Int(floor(number / 2.0)) + 1
    }
}
