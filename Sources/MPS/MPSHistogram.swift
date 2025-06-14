//
//  MPSHistogram.swift
//  Harbeth
//
//  Created by Condy on 2023/8/3.
//

import Foundation
import MetalPerformanceShaders
import simd

// Note: @unchecked Sendable is used because this struct holds non-Sendable MPSImageHistogram/Equalization. Ensure thread-safe usage.
public struct MPSHistogram: MPSKernelProtocol, @unchecked Sendable {
    
    private let metalDevice: MTLDevice
    public static let range: ParameterRange<Int, MPSHistogram> = .init(min: 0, max: 8, value: 2)
    
    @Clamping(MPSHistogram.range.min...MPSHistogram.range.max) public var histogramEntries: Int = MPSHistogram.range.value {
        didSet {
            var histogramInfo = MPSHistogram.createMPSImageHistogramInfo(histogramEntries)
            self.histogram = MPSImageHistogram(device: self.metalDevice, histogramInfo: &histogramInfo)
            self.histogram.zeroHistogram = false // Ensure this is set in didSet as well
            self.equalization = MPSImageHistogramEqualization(device: self.metalDevice, histogramInfo: &histogramInfo)
        }
    }
    
    public var modifier: Modifier {
        return .mps(performance: self.histogram)
    }
    
    public func encode(commandBuffer: MTLCommandBuffer, textures: [MTLTexture]) throws -> MTLTexture {
        let destinationTexture = textures[0]
        let sourceTexture = textures[1]
        let bufferLength = histogram.histogramSize(forSourceFormat: sourceTexture.pixelFormat)
        guard let histogramBuffer = self.metalDevice.makeBuffer(length: bufferLength, options: [.storageModePrivate]) else {
            return destinationTexture
        }
        histogram.encode(to: commandBuffer, sourceTexture: sourceTexture, histogram: histogramBuffer, histogramOffset: 0)
        // 根据直方图计算累加直方图数据
        equalization.encodeTransform(to: commandBuffer, sourceTexture: sourceTexture, histogram: histogramBuffer, histogramOffset: 0)
        // 最后进行均衡化处理
        equalization.encode(commandBuffer: commandBuffer, sourceTexture: sourceTexture, destinationTexture: destinationTexture)
        return destinationTexture
    }
    
    private var histogram: MPSImageHistogram
    private var equalization: MPSImageHistogramEqualization
    
    public init(histogramEntries: Int = MPSHistogram.range.value) async {
        self.metalDevice = await Device.device()
        var histogramInfo = MPSHistogram.createMPSImageHistogramInfo(histogramEntries)
        self.histogram = MPSImageHistogram(device: self.metalDevice, histogramInfo: &histogramInfo)
        self.histogram.zeroHistogram = false
        self.equalization = MPSImageHistogramEqualization(device: self.metalDevice, histogramInfo: &histogramInfo)
    }
}

extension MPSHistogram {
    /// 创建计算直方图数据
    private static func createMPSImageHistogramInfo(_ histogramEntries: Int) -> MPSImageHistogramInfo {
        let value = min(max(histogramEntries, MPSHistogram.range.min), MPSHistogram.range.max)
        // See: https://stackoverflow.com/questions/58387519/mpsimagehistogramequalization-throws-assertion-that-offset-must-be-buffer-len
        let entries = Int(truncating: NSDecimalNumber(decimal: pow(2, value))) * 256
        return MPSImageHistogramInfo(numberOfHistogramEntries: entries,
                                     histogramForAlpha: false,
                                     minPixelValue: vector_float4(0,0,0,0),
                                     maxPixelValue: vector_float4(1,1,1,1))
    }
}
