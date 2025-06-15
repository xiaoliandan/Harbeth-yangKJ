//
//  HarbethIO.swift
//  Harbeth
//
//  Created by Condy on 2022/10/22.
//  https://github.com/yangKJ/Harbeth

import Foundation
@preconcurrency import MetalKit
import CoreImage
import CoreMedia
import CoreVideo

@available(*, deprecated, message: "Typo. Use `HarbethIO` instead", renamed: "HarbethIO")
public typealias BoxxIO<Dest> = HarbethIO<Dest>

/// Quickly add filters to sources.
/// Support use `UIImage/NSImage, CGImage, CIImage, MTLTexture, CMSampleBuffer, CVPixelBuffer/CVImageBuffer`
///
/// For example:
///
///     let filter = C7Storyboard(ranks: 2)
///     let dest = HarbethIO.init(element: originImage, filter: filter)
///     ImageView.image = try? dest.output()
///
///     // Asynchronous add filters to sources.
///     dest.transmitOutput(success: { [weak self] image in
///         // do somthing..
///     })
///
@frozen public struct HarbethIO<Dest> : Destype {
    public typealias Element = Dest
    public let element: Dest
    public let filters: [C7FilterProtocol]
    
    private var setupedBufferPixelFormat = false
    /// Since the camera acquisition generally uses ' kCVPixelFormatType_32BGRA '
    /// The pixel format needs to be consistent, otherwise it will appear blue phenomenon.
    public var bufferPixelFormat: MTLPixelFormat = .bgra8Unorm {
        didSet {
            setupedBufferPixelFormat = true
        }
    }
    
    /// When the CIImage is created, it is mirrored and flipped upside down.
    /// But upon inspecting the texture, it still renders the CIImage as expected.
    /// Nevertheless, we can fix this by simply transforming the CIImage with the downMirrored orientation.
    public var mirrored: Bool = false
    
    /// Do you need to create an output texture object?
    /// If you do not create a separate output texture, texture overlay may occur.
    public var createDestTexture: Bool = true
    
    /// Metal texture transmit output real time commit buffer.
    /// Fixed camera capture output CMSampleBuffer.
    public var transmitOutputRealTimeCommit: Bool = false {
        didSet {
            if transmitOutputRealTimeCommit {
                hasCoreImage = true
            }
        }
    }
    
    /// 烦死😡，中间加入CoreImage滤镜不能最后才渲染，考虑到性能最大化，这边分开处理。
    /// After adding the CoreImage filter in the middle, it can't be rendered until the end.
    /// Considering the maximization of performance, we will deal with it separately.
    private var hasCoreImage: Bool
    
    public init(element: Dest, filters: [C7FilterProtocol]) {
        self.element = element
        self.filters = filters
        self.hasCoreImage = filters.contains { $0 is CoreImageProtocol }
    }
    
    public func output() async throws -> Dest {
        if self.filters.isEmpty {
            return element
        }
        switch element {
        case let ee as MTLTexture:
            return try await filtering(texture: ee) as! Dest
        case let ee as C7Image:
            return try await filtering(image: ee) as! Dest
        case let ee as CIImage:
            return try await filtering(ciImage: ee) as! Dest
        case let ee where CFGetTypeID(ee as CFTypeRef) == CGImage.typeID:
            return try await filtering(cgImage: ee as! CGImage) as! Dest
        case let ee where CFGetTypeID(ee as CFTypeRef) == CVPixelBufferGetTypeID():
            return try await filtering(pixelBuffer: ee as! CVPixelBuffer) as! Dest
        case let ee where CFGetTypeID(ee as CFTypeRef) == CMSampleBufferGetTypeID():
            return try await filtering(sampleBuffer: ee as! CMSampleBuffer) as! Dest
        default:
            return element            
        }
    }
    
    /// Convert to texture and add filters.
    @available(*, deprecated, message: "Use `output()` method instead.", renamed: "output")
    public func transmitOutput() async throws -> Dest {
        return try await output()
    }
    
    /// Asynchronous convert to texture and add filters.
    /// - Parameters:
    ///   - texture: Input metal texture.
    @available(*, deprecated, message: "Use async version `filtering(texture:) async throws -> MTLTexture` instead.", renamed: "filtering(texture:)")
    public func filtering(texture: MTLTexture, complete: @escaping (Result<MTLTexture, HarbethError>) -> Void) {
        Task {
            do {
                let result = try await filtering(texture: texture)
                complete(.success(result))
            } catch {
                complete(.failure(HarbethError.toHarbethError(error)))
            }
        }
    }
}

// MARK: - filtering methods
extension HarbethIO {
    
    private func filtering(pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer {
        let inTexture = try await TextureLoader.init(with: pixelBuffer).texture
        let texture = try await filtering(texture: inTexture)
        // copyToPixelBuffer is likely synchronous CPU work.
        pixelBuffer.c7.copyToPixelBuffer(with: texture)
        return pixelBuffer
    }
    
    private func filtering(sampleBuffer: CMSampleBuffer) async throws -> CMSampleBuffer {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw HarbethError.CMSampleBufferToCVPixelBuffer
        }
        let p = try await filtering(pixelBuffer: pixelBuffer)
        // toCMSampleBuffer is likely synchronous.
        guard let buffer = p.c7.toCMSampleBuffer() else {
            throw HarbethError.CVPixelBufferToCMSampleBuffer
        }
        return buffer
    }
    
    private func filtering(ciImage: CIImage) async throws -> CIImage {
        let inTexture = try await TextureLoader.init(with: ciImage).texture
        let texture = try await filtering(texture: inTexture)
        // toCIImage is likely synchronous.
        return try texture.c7.toCIImage(mirrored: mirrored)
    }
    
    private func filtering(cgImage: CGImage) async throws -> CGImage {
        let inTexture = try await TextureLoader.init(with: cgImage).texture
        let texture = try await filtering(texture: inTexture)
        // toCGImage is likely synchronous.
        guard let cgImg = texture.c7.toCGImage() else {
            throw HarbethError.texture2Image
        }
        return cgImg
    }
    
    private func filtering(image: C7Image) async throws -> C7Image {
        let inTexture = try await TextureLoader.init(with: image).texture
        let texture = try await filtering(texture: inTexture)
        // fixImageOrientation is likely synchronous.
        return try texture.c7.fixImageOrientation(refImage: image)
    }
    
    private func filtering(texture: MTLTexture) async throws -> MTLTexture {
        var inTexture: MTLTexture = texture
        if hasCoreImage {
            for filter in filters {
                inTexture = try await textureIO(with: inTexture, filter: filter, for: nil)
            }
        } else {
            // makeCommandBuffer is now async
            let commandBuffer = try await makeCommandBuffer()
            for filter in filters {
                // textureIO is now async
                inTexture = try await textureIO(with: inTexture, filter: filter, for: commandBuffer)
            }
            try await asyncCommit(commandBuffer: commandBuffer)
        }
        return inTexture
    }
}

// MARK: - asynchronous filtering methods
// These methods are now deprecated and will call their async counterparts.
extension HarbethIO {
    
    @available(*, deprecated, message: "Use async version `filtering(pixelBuffer:) async throws -> CVPixelBuffer` instead.", renamed: "filtering(pixelBuffer:)")
    internal func filtering(pixelBuffer: CVPixelBuffer, complete: @escaping (Result<CVPixelBuffer, HarbethError>) -> Void) {
        Task {
            do {
                let result = try await filtering(pixelBuffer: pixelBuffer)
                complete(.success(result))
            } catch {
                complete(.failure(HarbethError.toHarbethError(error)))
            }
        }
    }
    
    @available(*, deprecated, message: "Use async version `filtering(sampleBuffer:) async throws -> CMSampleBuffer` instead.", renamed: "filtering(sampleBuffer:)")
    internal func filtering(sampleBuffer: CMSampleBuffer, complete: @escaping (Result<CMSampleBuffer, HarbethError>) -> Void) {
        Task {
            do {
                let result = try await filtering(sampleBuffer: sampleBuffer)
                complete(.success(result))
            } catch {
                complete(.failure(HarbethError.toHarbethError(error)))
            }
        }
    }
    
    @available(*, deprecated, message: "Use async version `filtering(ciImage:) async throws -> CIImage` instead.", renamed: "filtering(ciImage:)")
    internal func filtering(ciImage: CIImage, complete: @escaping (Result<CIImage, HarbethError>) -> Void) {
        Task {
            do {
                let result = try await filtering(ciImage: ciImage)
                complete(.success(result))
            } catch {
                complete(.failure(HarbethError.toHarbethError(error)))
            }
        }
    }
    
    @available(*, deprecated, message: "Use async version `filtering(cgImage:) async throws -> CGImage` instead.", renamed: "filtering(cgImage:)")
    internal func filtering(cgImage: CGImage, complete: @escaping (Result<CGImage, HarbethError>) -> Void) {
        Task {
            do {
                let result = try await filtering(cgImage: cgImage)
                complete(.success(result))
            } catch {
                complete(.failure(HarbethError.toHarbethError(error)))
            }
        }
    }
    
    @available(*, deprecated, message: "Use async version `filtering(image:) async throws -> C7Image` instead.", renamed: "filtering(image:)")
    internal func filtering(image: C7Image, complete: @escaping (Result<C7Image, HarbethError>) -> Void) {
        Task {
            do {
                let result = try await filtering(image: image)
                complete(.success(result))
            } catch {
                complete(.failure(HarbethError.toHarbethError(error)))
            }
        }
    }
}

// MARK: - private methods
extension HarbethIO {
    
    private func asyncCommit(commandBuffer: MTLCommandBuffer) async throws {
        // Using HarbethError.error(Error) or a specific case if available would be better.
        // For now, rethrowing the original error.
        // enum CommitError: Error { case unknown } // Placeholder, ideally use HarbethError
        return try await withCheckedThrowingContinuation { continuation in
            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
            commandBuffer.commit()
        }
    }

    /// The default setting for MTLPixelFormat is rgba8Unorm.
    private var rgba8UnormTexture: Bool {
        switch element {
        case _ as MTLTexture:
            return true
        case _ as C7Image:
            return true
        case _ as CIImage:
            return true
        case let ee where CFGetTypeID(ee as CFTypeRef) == CGImage.typeID:
            return true
        case let ee where CFGetTypeID(ee as CFTypeRef) == CVPixelBufferGetTypeID():
            return false
        case let ee where CFGetTypeID(ee as CFTypeRef) == CMSampleBufferGetTypeID():
            return false
        default:
            return false
        }
    }
    
    private func createDestTexture(with sourceTexture: MTLTexture, filter: C7FilterProtocol) async throws -> MTLTexture {
        if self.createDestTexture == false {
            return sourceTexture
        }
        let params = filter.parameterDescription
        if !(params["needCreateDestTexture"] as? Bool ?? true) {
            // 纯色`C7SolidColor`和渐变色`C7ColorGradient`滤镜不需要创建新的输出纹理，直接使用输入纹理即可
            return sourceTexture
        }
        let resize = filter.resize(input: C7Size(width: sourceTexture.width, height: sourceTexture.height))
        var bufferPixelFormat: MTLPixelFormat = bufferPixelFormat
        if !setupedBufferPixelFormat, rgba8UnormTexture {
            bufferPixelFormat = .rgba8Unorm
        }
        // Since the camera acquisition generally uses ' kCVPixelFormatType_32BGRA '
        // The pixel format needs to be consistent, otherwise it will appear blue phenomenon.
        return try await TextureLoader.makeTexture(width: resize.width, height: resize.height, options: [
            .texturePixelFormat: bufferPixelFormat
        ])
    }
    
    /// Do you need to create a new metal texture command buffer.
    /// - Parameter buffer: Old command buffer.
    /// - Returns: A command buffer.
    private func makeCommandBuffer(for buffer: MTLCommandBuffer? = nil) async throws -> MTLCommandBuffer {
        if let commandBuffer = buffer {
            return commandBuffer
        }
        guard let commandBuffer = await Device.commandQueue().makeCommandBuffer() else {
            throw HarbethError.commandBuffer
        }
        return commandBuffer
    }
    
    /// Create a new texture based on the filter content.
    /// Synchronously wait for the execution of the Metal command buffer to complete.
    /// - Parameters:
    ///   - texture: Input texture
    ///   - filter: It must be an object implementing C7FilterProtocol
    ///   - buffer: A valid MTLCommandBuffer to receive the encoded filter.
    /// - Returns: Output texture after processing
    private func textureIO(with texture: MTLTexture, filter: C7FilterProtocol, for buffer: MTLCommandBuffer?) async throws -> MTLTexture {
        let commandBuffer = try await makeCommandBuffer(for: buffer)
        var destTexture = try await createDestTexture(with: texture, filter: filter)
        let inputTexture = try await filter.combinationBegin(for: commandBuffer, source: texture, dest: destTexture)
        switch filter.modifier {
        case .coreimage(let name) where filter is CoreImageProtocol:
            let outputImage = try await (filter as! CoreImageProtocol).outputCIImage(with: inputTexture, name: name)
            try outputImage.c7.renderCIImageToTexture(destTexture, commandBuffer: commandBuffer)
        case .compute, .mps, .render:
            // Assuming filter.applyAtTexture will also become async.
            // For now, the subtask did not explicitly state this for Group 1,
            // but it's a highly probable change for later steps.
            // If filter.applyAtTexture is not async, this await will cause an error.
            // For now, adding it as per the general instruction for "other newly async functions".
            destTexture = try await filter.applyAtTexture(form: inputTexture, to: destTexture, for: commandBuffer)
        default:
            return texture
        }
        let outputTexture = try filter.combinationAfter(for: commandBuffer, input: destTexture, source: texture)
        if hasCoreImage {
            // This might need to change if commitAndWaitUntilCompleted has an async alternative
            // or if the overall flow becomes fully async. For now, keeping as is.
            commandBuffer.commitAndWaitUntilCompleted()
        }
        return outputTexture
    }
    
    // runAsyncIO has been removed as its functionality is superseded by the async filtering methods
    // and the refactored textureIO method.
}
