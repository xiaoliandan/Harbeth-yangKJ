@preconcurrency import Metal
//
//  Device.swift
//  Harbeth
//
//  Created by Condy on 2021/8/8.
//

import Foundation
import MetalKit
import VideoToolbox
@preconcurrency import CoreImage

/// Global public information
public actor Device: Cacheable {

    // TextureCache
    var textureCache: CVMetalTextureCache?
    
    /// Device information to create other objects
    /// MTLDevice creation is expensive, time-consuming, and can be used forever, so you only need to create it once
    let device: MTLDevice
    /// Single command queue
    let commandQueue: MTLCommandQueue
    /// Metal file in your local project
    let defaultLibrary: MTLLibrary?
    /// Metal file in ``Harbeth Framework``
    let harbethLibrary: MTLLibrary?
    /// Cache pipe state
    lazy var pipelines = [C7KernelFunction: MTLComputePipelineState]()
    /// Load the texture tool
    lazy var textureLoader: MTKTextureLoader = MTKTextureLoader(device: device)
    /// Transform using color space
    lazy var colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    /// We are likely to encounter images with wider colour than sRGB
    lazy var workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    /// CIContexts
    lazy var contexts = [CGColorSpace: CIContext]()
    
    init() async {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Could not create Metal Device")
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = queue
        
        // Initialize texture cache
        var cache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) != kCVReturnSuccess {
            // Handle error or set to nil
            cache = nil
        }
        self.textureCache = cache

        // Since min deployment is iOS 18 & macOS 15, this check is always true.
        self.defaultLibrary = try? device.makeDefaultLibrary(bundle: Bundle.main)
        // } else {
        //     self.defaultLibrary = device.makeDefaultLibrary()
        // }
        self.harbethLibrary = await Device.makeFrameworkLibrary(device, for: "Harbeth")
        
        if defaultLibrary == nil && harbethLibrary == nil {
            HarbethError.failed("Could not load library")
        }
    }
    
    deinit {
        print("Device is deinit.")
    }
}

extension Device {
    
    public static func makeFrameworkLibrary(_ device: MTLDevice, for resource: String) async -> MTLLibrary? {
        #if SWIFT_PACKAGE
        /// Fixed the Swift PM cannot read the `.metal` file.
        /// https://stackoverflow.com/questions/63237395/generating-resource-bundle-accessor-type-bundle-has-no-member-module
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            return library
        }
        if let pathURL = Bundle.module.url(forResource: "default", withExtension: "metallib") {
            // pathURL is already a URL
            if let library = try? device.newLibrary(URL: pathURL) {
                return library
            }
        }
        #endif
        
        /// Fixed the read failure of imported local resources was rectified.
        if let library = try? device.makeDefaultLibrary(bundle: Bundle(for: Device.self)) {
            return library
        }
        
        let bundle = await R.readFrameworkBundle(with: resource)
        /// Fixed libraryFile is nil. podspec file `s.static_framework = false`
        /// https://github.com/CocoaPods/CocoaPods/issues/7967
        guard let libraryFile = bundle?.path(forResource: "default", ofType: "metallib") else { // Should be libraryFileOrPath if used below, or use libraryFile
            return nil
        }
        
        let fileURL = URL(fileURLWithPath: libraryFile) // Corrected to libraryFile
        /// Compatible with the Bundle address used by CocoaPods to import framework.
        // The makeLibrary(filepath:) was deprecated in iOS 14.0+
        // The makeLibrary(URL:) was deprecated in iOS 16.0+
        // Using newLibrary(URL:) which is available iOS 8.0+
        if let library = try? device.newLibrary(URL: fileURL) {
            return library
        }
        
        // This #available block for makeLibrary(URL:) is now redundant due to newLibrary(URL:) above,
        // and also because min deployment (iOS 18, macOS 15) is far above macOS 10.13 / iOS 11.0.
        // if #available(macOS 10.13, iOS 11.0, *) {
        //     if let library = try? device.newLibrary(URL: fileURL) {
        //         return library
        //     }
        // }
        
        return nil
    }
    
    static func readMTLFunction(_ name: String) async throws -> MTLFunction {
        let deviceActor = await Shared.shared.getInitializedDevice()
        // First read the project
        if let libray = await deviceActor.defaultLibrary, let function = libray.makeFunction(name: name) {
            return function
        }
        // Then read from ``Harbeth Framework``
        if let libray = await deviceActor.harbethLibrary, let function = libray.makeFunction(name: name) {
            return function
        }
        #if DEBUG
        fatalError(HarbethError.readFunction(name).localizedDescription)
        #else
        throw HarbethError.readFunction(name)
        #endif
    }
}

extension Device {
    
    // Mutating func to update contexts dictionary
    func setContext(_ context: CIContext, for key: CGColorSpace) {
        self.contexts[key] = context
    }

    public func getCachedContext(for colorSpace: CGColorSpace) -> CIContext? {
        return contexts[colorSpace]
    }

    public func cachedComputePipelineState(for kernel: String) async throws -> MTLComputePipelineState {
        // Access actor's own 'pipelines' dictionary
        if let pipelineState = self.pipelines[kernel] {
            return pipelineState
        }

        // Call the static 'Device.readMTLFunction'. This function is okay as it
        // internally (and correctly) awaits the shared Device actor instance
        // to access library properties for creating the MTLFunction.
        let function = try await Device.readMTLFunction(kernel)

        // Use actor's own 'device' property to create the pipeline state
        let newPipelineState: MTLComputePipelineState
        do {
            newPipelineState = try await self.device.makeComputePipelineState(function: function)
        } catch {
            // Assuming HarbethError.computePipelineState(kernel) exists
            // If not, rethrow or wrap in a generic error. For now, let's assume it does or rethrow.
            // For the purpose of this subtask, directly throwing the error from makeComputePipelineState is acceptable.
             throw error // Or a specific HarbethError
        }

        // Store in actor's own 'pipelines' dictionary
        self.pipelines[kernel] = newPipelineState
        return newPipelineState
    }

    // Add to public actor Device scope
    public func texture(from pixelBuffer: CVPixelBuffer, usage: MTLTextureUsage = .shaderRead) async throws -> MTLTexture {
        guard let anUnsafeTextureCache = self.textureCache else {
            // Define HarbethError.textureCacheIsNil or use a generic error
            throw NSError(domain: "Harbeth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Texture cache is nil."])
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvMetalTextureUnmanaged: CVMetalTexture?

        // Assuming bgra8Unorm for now as a common format from CVPixelBuffers.
        // This might need to be inferred or passed as a parameter.
        let mtlPixelFormat: MTLPixelFormat = .bgra8Unorm

        // CVMetalTextureCacheCreateTextureFromImage uses UnsafeMutablePointer<CVMetalTexture?>
        // So we pass the address of cvMetalTextureUnmanaged
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                              anUnsafeTextureCache, // CVMetalTextureCache (bridged)
                                                              pixelBuffer,        // CVPixelBuffer (bridged)
                                                              nil,                // textureAttributes (CFDictionary)
                                                              mtlPixelFormat,     // MTLPixelFormat
                                                              width,              // width (Int)
                                                              height,             // height (Int)
                                                              0,                  // planeIndex (Int)
                                                              &cvMetalTextureUnmanaged) // CVMetalTexture?

        guard status == kCVReturnSuccess else {
            // Define HarbethError.cvMetalTextureCreateFailure or use generic
            throw NSError(domain: "Harbeth", code: -2, userInfo: [NSLocalizedDescriptionKey: "CVMetalTextureCacheCreateTextureFromImage failed with status \(status)"])
        }

        guard let cvMetalTexture = cvMetalTextureUnmanaged else {
            // Define HarbethError.cvMetalTextureNilAfterCreation or use generic
            throw NSError(domain: "Harbeth", code: -3, userInfo: [NSLocalizedDescriptionKey: "CVMetalTexture is nil after successful creation."])
        }

        guard let mtlTexture = CVMetalTextureGetTexture(cvMetalTexture) else {
            // Define HarbethError.mtlTextureExtractionFailed or use generic
            throw NSError(domain: "Harbeth", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to get MTLTexture from CVMetalTexture."])
        }

        // The `usage` parameter currently isn't directly used to set MTLTexture.usage here,
        // as usage is generally determined at texture creation from a descriptor or by the cache.
        // This function primarily focuses on getting a texture from a CVPixelBuffer via the cache.
        // If specific usage enforcement is needed, it might involve checking mtlTexture.usage
        // or more complex cache configuration.

        return mtlTexture
    }

    public static func device() async -> MTLDevice {
        let dActor = await Shared.shared.getInitializedDevice()
        return await dActor.device
    }
    
    public static func colorSpace() async -> CGColorSpace {
        let dActor = await Shared.shared.getInitializedDevice()
        return await dActor.colorSpace
    }
    
    public static func bitmapInfo() -> UInt32 {
        // You can't get `CGImage.bitmapInfo` here, otherwise the heic and heif formats will turn blue.
        // Fixed draw bitmap after applying filter image color rgba => bgra.
        // See：https://github.com/yangKJ/Harbeth/issues/12
        return CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    }
    
    public static func commandQueue() async -> MTLCommandQueue {
        let dActor = await Shared.shared.getInitializedDevice()
        return await dActor.commandQueue
    }
    
    // @MainActor public static func sharedTextureCache() async -> CVMetalTextureCache? {
    //     // FIXME: Deprecated. Use Device actor's texture(from:usage:) method instead.
    //     let dActor = await Shared.shared.getInitializedDevice()
    //     return await dActor.getTextureCache()
    // }
    
    @MainActor public static func context() async -> CIContext {
        return await Device.context(colorSpace: await Device.colorSpace())
    }
    
    @MainActor public static func context(cgImage: CGImage) async -> CIContext {
        let cs = cgImage.colorSpace ?? (await Device.colorSpace())
        return await Device.context(colorSpace: cs)
    }
    
    @MainActor public static func context(colorSpace: CGColorSpace) async -> CIContext {
        let deviceActor = await Shared.shared.getInitializedDevice()
        if let cachedContext = await deviceActor.getCachedContext(for: colorSpace) {
            return cachedContext
        }
        var options: [CIContextOption : Any] = [
            CIContextOption.outputColorSpace: colorSpace,
            // Caching does provide a minor speed boost without ballooning memory use, so let's have it on
            CIContextOption.cacheIntermediates: true,
            // Low GPU priority would make sense for a background operation that isn't performance-critical,
            // but we are interested in disk-to-display performance
            CIContextOption.priorityRequestLow: false,
            // Definitely no CPU rendering, please
            CIContextOption.useSoftwareRenderer: false,
            // This is the Apple recommendation, see cgImage(using:) above
            CIContextOption.workingFormat: CIFormat.RGBAh,
        ]
        // Since min deployment is iOS 18 & macOS 15, this check is always true.
        // if #available(iOS 13.0, macOS 10.12, *) {
        // This option is undocumented, possibly only effective on iOS?
        // Sounds more like allowLowPerformance, though, so turn it off
        options[CIContextOption.allowLowPower] = false
        // }
        if let workingColorSpace = await deviceActor.workingColorSpace {
            // We are likely to encounter images with wider colour than sRGB
            options[CIContextOption.workingColorSpace] = workingColorSpace
        }
        let context: CIContext
        // Use device and commandQueue directly from the actor instance
        let mtlDevice = await deviceActor.device
        let mtlCommandQueue = await deviceActor.commandQueue

        // Since min deployment is iOS 18 & macOS 15, this is always the path taken.
        context = CIContext(mtlCommandQueue: mtlCommandQueue, options: options)
        // } else if #available(iOS 9.0, *, macOS 10.11, *) {
        //     context = CIContext(mtlDevice: mtlDevice, options: options)
        // } else {
        //     context = CIContext(options: options)
        // }
        await deviceActor.setContext(context, for: colorSpace) // Call the new mutating func
        return context
    }
}
