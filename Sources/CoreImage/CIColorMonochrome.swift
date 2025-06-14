//
//  CIColorMonochrome.swift
//  Harbeth
//
//  Created by Condy on 2024/3/3.
//

import Foundation
import CoreImage

/// 单色滤镜
public struct CIColorMonochrome: CoreImageProtocol, Sendable {
    
    public static let range: ParameterRange<Float, Self> = .init(min: 0.0, max: 1.0, value: 1.0)
    
    @Clamping(range.min...range.max) public var intensity: Float = range.value
    
    public var redComponent: Float
    public var greenComponent: Float
    public var blueComponent: Float
    public var alphaComponent: Float
    
    public var modifier: Modifier {
        return .coreimage(CIName: "CIColorMonochrome")
    }
    
    public func coreImageApply(filter: CIFilter, input ciImage: CIImage) throws -> CIImage {
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        let coreImageColor = CIColor(red: CGFloat(self.redComponent), green: CGFloat(self.greenComponent), blue: CGFloat(self.blueComponent), alpha: CGFloat(self.alphaComponent))
        filter.setValue(coreImageColor, forKey: kCIInputColorKey)
        return ciImage
    }
    
    public init(color: C7Color = .white) {
        let (r, g, b, a) = color.c7.toRGBA()
        self.redComponent = r
        self.greenComponent = g
        self.blueComponent = b
        self.alphaComponent = a
    }
}
