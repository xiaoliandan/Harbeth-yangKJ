//
//  TextureLoader.swift
//  Harbeth
//
//  Created by Condy on 2023/8/8.
//

import Foundation
@preconcurrency import MetalKit
import CoreImage

/// Convert to metal texture Or create empty metal texture.
public struct TextureLoader {
    
    private static let usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
    /// Default create metal texture parameters.
    public static let defaultOptions = [
        .textureUsage: NSNumber(value: TextureLoader.usage.rawValue),
        .generateMipmaps: NSNumber(value: false),
        .SRGB: NSNumber(value: false),
        .textureCPUCacheMode: NSNumber(value: true),
    ] as [MTKTextureLoader.Option: NSNumber]
    
    public static let shaderReadTextureOptions = [
        .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
        .generateMipmaps: NSNumber(value: false),
        .SRGB: NSNumber(value: false),
        .textureCPUCacheMode: NSNumber(value: true),
    ] as [MTKTextureLoader.Option: NSNumber]
    
    /// A metal texture.
    public let texture: MTLTexture
    
    /// Is it a blank texture?
    public var isBlank: Bool {
        texture.c7.isBlank()
    }
    
    public init(with texture: MTLTexture) {
        self.texture = texture
    }
    
    /// Creates a new MTLTexture from a given bitmap image.
    /// - Parameters:
    ///   - cgImage: Bitmap image
    ///   - options: Dictonary of MTKTextureLoaderOptions.
    public init(with cgImage: CGImage, options: [MTKTextureLoader.Option: Any]? = nil) async throws {
        let deviceInstance = await Shared.shared.getInitializedDevice()
        let loader = deviceInstance.textureLoader
        let finalOptions = options ?? TextureLoader.defaultOptions
        self.texture = try loader.newTexture(cgImage: cgImage, options: finalOptions)
    }
    
    /// Creates a new MTLTexture from a CIImage.
    /// - Parameters:
    ///   - ciImage: CIImage
    ///   - options: Dictonary of MTKTextureLoaderOptions.
    public init(with ciImage: CIImage, options: [MTKTextureLoader.Option: Any]? = nil) async throws {
        let finalOptions = options ?? TextureLoader.defaultOptions
        let context: CIContext? = {
            if finalOptions.keys.contains(where: { $0 == .sharedContext }) {
                return finalOptions[.sharedContext] as? CIContext
            }
            return nil
        }()
        guard let cgImage = ciImage.c7.toCGImage(context: context) else {
            throw HarbethError.source2Texture
        }
        try await self.init(with: cgImage, options: finalOptions)
    }
    
    /// Creates a new MTLTexture from a CVPixelBuffer.
    /// - Parameters:
    ///   - ciImage: CVPixelBuffer
    ///   - options: Dictonary of MTKTextureLoaderOptions.
    public init(with pixelBuffer: CVPixelBuffer, options: [MTKTextureLoader.Option: Any]? = nil) async throws {
        guard let cgImage = pixelBuffer.c7.toCGImage() else {
            throw HarbethError.source2Texture
        }
        let finalOptions = options ?? TextureLoader.defaultOptions
        try await self.init(with: cgImage, options: finalOptions)
    }
    
    /// Creates a new MTLTexture from a CMSampleBuffer.
    /// - Parameters:
    ///   - ciImage: CVPixelBuffer
    ///   - options: Dictonary of MTKTextureLoaderOptions.
    public init(with sampleBuffer: CMSampleBuffer, options: [MTKTextureLoader.Option: Any]? = nil) async throws {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw HarbethError.CMSampleBufferToCVPixelBuffer
        }
        let finalOptions = options ?? TextureLoader.defaultOptions
        // Since init(with pixelBuffer:) is now async, we await it.
        try await self.init(with: pixelBuffer, options: finalOptions)
    }
    
    /// Creates a new MTLTexture from a UIImage / NSImage.
    /// - Parameters:
    ///   - image: A UIImage / NSImage.
    ///   - options: Dictonary of MTKTextureLoaderOptions.
    public init(with image: C7Image, options: [MTKTextureLoader.Option: Any]? = nil) async throws {
        guard let cgImage = image.c7.toCGImage() else {
            throw HarbethError.image2CGImage
        }
        let finalOptions = options ?? TextureLoader.defaultOptions
        try await self.init(with: cgImage, options: finalOptions)
    }
    
    /// Creates a new MTLTexture from a Data.
    /// - Parameters:
    ///   - data: Data.
    ///   - options: Dictonary of MTKTextureLoaderOptions.
    public init(with data: Data, options: [MTKTextureLoader.Option: Any]? = nil) async throws {
        let deviceInstance = await Shared.shared.getInitializedDevice()
        let loader = deviceInstance.textureLoader
        let finalOptions = options ?? TextureLoader.defaultOptions
        self.texture = try loader.newTexture(data: data, options: finalOptions)
    }
    
    #if os(macOS)
    /// Creates a new MTLTexture from a NSBitmapImageRep.
    /// - Parameters:
    ///   - bitmap: NSBitmapImageRep.
    ///   - pixelFormat: Indicates the pixelFormat, The format of the picture should be consistent with the data.
    public init(with bitmap: NSBitmapImageRep, pixelFormat: MTLPixelFormat = .rgba8Unorm) async throws {
        guard let data: UnsafeMutablePointer<UInt8> = bitmap.bitmapData else {
            throw HarbethError.bitmapDataNotFound
        }
        let texture = try await TextureLoader.emptyTexture(width: Int(bitmap.size.width), height: Int(bitmap.size.height), options: [
            .texturePixelFormat: pixelFormat,
        ])
        let region = MTLRegionMake2D(0, 0, bitmap.pixelsWide, bitmap.pixelsHigh)
        texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: bitmap.bytesPerRow)
        self.texture = texture
    }
    #endif
}

// MARK: - create empty metal texture
extension TextureLoader {
    /// Create a new metal texture with options.
    public struct Option : Hashable, Equatable, RawRepresentable, @unchecked Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
    }
    
    /// Create a new MTLTexture for later storage according to the texture parameters.
    /// - Parameters:
    ///   - size: The texture size.
    ///   - options: Configure other parameters about generating metal textures.
    public static func makeTexture(at size: CGSize, options: [TextureLoader.Option: Any]? = nil) async throws -> MTLTexture {
        try await makeTexture(width: Int(size.width), height: Int(size.height), options: options)
    }
    
    /// Create a new MTLTexture for later storage according to the texture parameters.
    /// - Parameters:
    ///   - width: The texture width, must be greater than 0, maximum resolution is 16384.
    ///   - height: The texture height, must be greater than 0, maximum resolution is 16384.
    ///   - options: Configure other parameters about generating metal textures.
    public static func makeTexture(width: Int, height: Int, options: [TextureLoader.Option: Any]? = nil) async throws -> MTLTexture {
        let options = options ?? [TextureLoader.Option: Any]()
        var usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
        var pixelFormat = MTLPixelFormat.rgba8Unorm
        var storageMode = MTLStorageMode.shared
        var allowGPUOptimizedContents = true
        #if os(macOS) || targetEnvironment(macCatalyst)
        // Texture Descriptor Validation MTLStorageModeShared not allowed for textures.
        // So macOS need use `managed`.
        storageMode = MTLStorageMode.managed
        #endif
        var sampleCount: Int = 1
        for (key, value) in options {
            switch (key, value) {
            case (.texturePixelFormat, let value as MTLPixelFormat):
                pixelFormat = value
            case (.textureUsage, let value as MTLTextureUsage):
                usage = value
            case (.textureStorageMode, let value as MTLStorageMode):
                storageMode = value
            case (.textureSampleCount, let value as Int):
                sampleCount = value
            case (.textureAllowGPUOptimizedContents, let value as Bool):
                allowGPUOptimizedContents = value
            default:
                break
            }
        }
        // Create a TextureDescriptor for a common 2D texture.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: min(max(1, width), 16_384),
            height: min(max(1, height), 16_384),
            mipmapped: sampleCount == 1
        )
        descriptor.usage = usage
        descriptor.storageMode = storageMode
        descriptor.sampleCount = sampleCount
        descriptor.textureType = sampleCount > 1 ? .type2DMultisample : .type2D
        // Since min deployment is iOS 18 & macOS 15, this check is always true.
        descriptor.allowGPUOptimizedContents = allowGPUOptimizedContents
        // }
        guard let texture = (await Device.device()).makeTexture(descriptor: descriptor) else {
            throw HarbethError.makeTexture
        }
        return texture
    }
    
    public static func emptyTexture(at size: CGSize, options: [TextureLoader.Option: Any]? = nil) async throws -> MTLTexture {
        try await makeTexture(at: size, options: options)
    }
    
    public static func emptyTexture(width: Int, height: Int, options: [TextureLoader.Option: Any]? = nil) async throws -> MTLTexture {
        try await makeTexture(width: width, height: height, options: options)
    }
}

extension TextureLoader {
    /// Creates a new only read metal texture from a given bitmap image.
    /// - Parameter cgImage: Bitmap image
    public static func shaderReadTexture(with cgImage: CGImage) async throws -> MTLTexture {
        try await TextureLoader.init(with: cgImage, options: TextureLoader.shaderReadTextureOptions).texture
    }
    
    /// Copy a new metal texture.
    /// - Parameter texture: Texture to be copied.
    /// - Returns: New metal texture.
    public static func copyTexture(with texture: MTLTexture) async throws -> MTLTexture {
        // 纹理最好不要又作为输入纹理又作为输出纹理，否则会出现重复内容，
        // 所以需要拷贝新的纹理来承载新的内容‼️
        return try await TextureLoader.makeTexture(width: texture.width, height: texture.height, options: [
            .texturePixelFormat: texture.pixelFormat,
            .textureUsage: texture.usage,
            .textureSampleCount: texture.sampleCount,
            .textureStorageMode: texture.storageMode,
        ])
    }
}

// MARK: - async convert to metal texture.
extension TextureLoader {
    
    public static func makeTexture(with cgImage: CGImage, options: [MTKTextureLoader.Option: Any]? = nil) async throws -> MTLTexture {
        let finalOptions = options ?? TextureLoader.defaultOptions
        let deviceInstance = await Shared.shared.getInitializedDevice()
        let loader = deviceInstance.textureLoader
        return try await withCheckedThrowingContinuation { continuation in
            loader.newTexture(cgImage: cgImage, options: finalOptions) { texture, error in
                if let texture = texture {
                    continuation.resume(returning: texture)
                } else if let error = error {
                    continuation.resume(throwing: HarbethError.error(error))
                } else {
                    continuation.resume(throwing: HarbethError.textureLoader) // Fallback error
                }
            }
        }
    }
    
    public static func makeTexture(with image: C7Image, options: [MTKTextureLoader.Option: Any]? = nil) async throws -> MTLTexture {
        guard let cgImage = image.cgImage else {
            throw HarbethError.image2CGImage
        }
        return try await makeTexture(with: cgImage, options: options)
    }
    
    public static func makeTexture(with ciImage: CIImage, options: [MTKTextureLoader.Option: Any]? = nil) async throws -> MTLTexture {
        let finalOptions = options ?? TextureLoader.defaultOptions
        let context: CIContext? = {
            if finalOptions.keys.contains(where: { $0 == .sharedContext }) {
                return finalOptions[.sharedContext] as? CIContext
            }
            return nil
        }()
        guard let cgImage = ciImage.c7.toCGImage(context: context) else {
            throw HarbethError.source2Texture
        }
        return try await makeTexture(with: cgImage, options: finalOptions)
    }
}

extension MTKTextureLoader.Option {
    /// Shared context.
    static let sharedContext: MTKTextureLoader.Option = .init(rawValue: "condy_context")
}

extension TextureLoader.Option {
    
    /// Indicates the pixelFormat, The format of the picture should be consistent with the data.
    /// The default is `MTLPixelFormat.rgba8Unorm`.
    public static let texturePixelFormat: TextureLoader.Option = .init(rawValue: 1 << 1)
    
    /// Description of texture usage, default is `shaderRead` and `shaderWrite`.
    /// MTLTextureUsage declares how the texture will be used over its lifetime (bitwise OR for multiple uses).
    /// This information may be used by the driver to make optimization decisions.
    public static let textureUsage: TextureLoader.Option = .init(rawValue: 1 << 2)
    
    /// Describes location and CPU mapping of MTLTexture.
    /// In this mode, CPU and device will nominally both use the same underlying memory when accessing the contents of the texture resource.
    /// However, coherency is only guaranteed at command buffer boundaries to minimize the required flushing of CPU and GPU caches.
    /// This is the default storage mode for iOS Textures.
    public static let textureStorageMode: TextureLoader.Option = .init(rawValue: 1 << 3)
    
    /// The number of samples in the texture to create. The default value is 1.
    /// When creating Buffer textures sampleCount must be 1. Implementations may round sample counts up to the next supported value.
    public static let textureSampleCount: TextureLoader.Option = .init(rawValue: 1 << 4)
    
    /// Allow GPU-optimization for the contents of this texture. The default value is true.
    public static let textureAllowGPUOptimizedContents: TextureLoader.Option = .init(rawValue: 1 << 5)
}
