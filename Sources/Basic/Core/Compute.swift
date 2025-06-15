//
//  Compute.swift
//  ATMetalBand
//
//  Created by Condy on 2022/2/13.
//

/// 文档
/// https://colin19941.gitbooks.io/metal-programming-guide-zh/content/Data-Parallel_Compute_Processing_Compute_Command_Encoder.html

import Foundation
import MetalKit
import Metal

internal struct Compute {
    /// Create a parallel computation pipeline.
    /// Performance intensive operations should not be invoked frequently
    /// - parameter kernel: Specifies the name of the data parallel computing coloring function
    /// - Returns: MTLComputePipelineState
    @inlinable static func makeComputePipelineState(with kernel: String) async throws -> MTLComputePipelineState {
        let sharedActor = Shared.shared // Get actor instance
        let sharedDeviceInstance = await sharedActor.getInitializedDevice() // Await device

        // Access pipelines on the Device instance.
        if let pipelineState = sharedDeviceInstance.pipelines[kernel] {
            return pipelineState
        }

        let function = try await Device.readMTLFunction(kernel)
        // Device.device() is now async, use the already fetched metalDevice from sharedDeviceInstance
        guard let pipeline = try? await sharedDeviceInstance.device.makeComputePipelineState(function: function) else {
            throw HarbethError.computePipelineState(kernel)
        }
        // pipelines is a var on Device, and Device is a class.
        // sharedDeviceInstance is a let constant holding the Device reference.
        sharedDeviceInstance.pipelines[kernel] = pipeline
        return pipeline
    }
    
    // Removed makeComputePipelineState with completion handler

    @inlinable static func makeCommandBuffer() async -> MTLCommandBuffer? {
        return await Device.commandQueue().makeCommandBuffer()
    }
}

extension C7FilterProtocol {
    
    func drawing(with kernel: String, commandBuffer: MTLCommandBuffer, textures: [MTLTexture]) async throws -> MTLTexture {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw HarbethError.makeComputeCommandEncoder
        }
        let pipelineState = try await Compute.makeComputePipelineState(with: kernel)
        
        return encoding(computeEncoder: computeEncoder, pipelineState: pipelineState, textures: textures)
    }
    
    // This completion handler version should be removed or updated to use async internally.
    // For this refactoring, as per similar changes, we remove it.
    // If it were to be kept and updated:
    // func drawing(with kernel: String, commandBuffer: MTLCommandBuffer, textures: [MTLTexture], complete: @escaping (Result<MTLTexture, HarbethError>) -> Void) {
    //     Task {
    //         do {
    //             guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
    //                 complete(.failure(HarbethError.makeComputeCommandEncoder))
    //                 return
    //             }
    //             let pipelineState = try await Compute.makeComputePipelineState(with: kernel)
    //             let destTexture = encoding(computeEncoder: computeEncoder, pipelineState: pipelineState, textures: textures)
    //             complete(.success(destTexture))
    //         } catch {
    //             complete(.failure(error as? HarbethError ?? HarbethError.unknown))
    //         }
    //     }
    // }
    
    private func encoding(computeEncoder: MTLComputeCommandEncoder, pipelineState: MTLComputePipelineState, textures: [MTLTexture]) -> MTLTexture {
        if case .compute(let kernel) = self.modifier {
            computeEncoder.label = kernel + " encoder"
        }
        computeEncoder.setComputePipelineState(pipelineState)
        let destTexture = textures[0]
        for (index, texture) in textures.enumerated() {
            computeEncoder.setTexture(texture, index: index)
        }
        
        let size = MemoryLayout<Float>.size
        for i in 0..<self.factors.count {
            var factor = self.factors[i]
            computeEncoder.setBytes(&factor, length: size, index: i)
        }
        /// 配置像素总数参数
        var index: Int = self.factors.count - 1
        if self.hasCount {
            var count = destTexture.width * destTexture.height
            computeEncoder.setBytes(&count, length: size, index: index)
            index += 1
        }
        /// 配置特殊参数非`Float`类型，例如4x4矩阵
        self.setupSpecialFactors(for: computeEncoder, index: index)
        
        // Too large some Gpus are not supported. Too small gpus have low efficiency
        // 2D texture, depth set to 1
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        // -1 pixel to solve the problem that the edges of images are not drawn.
        // Minimum 1 pixel, solve the problem of zero without drawing.
        let width  = max(Int((destTexture.width + threadgroupSize.width - 1) / threadgroupSize.width), 1)
        let height = max(Int((destTexture.height + threadgroupSize.height - 1) / threadgroupSize.height), 1)
        //let threadGroups = MTLSizeMake(width, height, destTexture.arrayLength)
        let threadgroupCount = MTLSize(width: width, height: height, depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        
        #if targetEnvironment(macCatalyst)
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        blitEncoder?.synchronize(resource: outputTexture)
        blitEncoder?.endEncoding()
        #endif
        
        return destTexture
    }
}
