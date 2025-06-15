//
//  Device.swift
//  Harbeth
//
//  Created by Condy on 2021/8/8.
//

import Foundation
import MetalKit

/// Global public information
public final class Device: Cacheable {
    
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
        
        if #available(iOS 10.0, macOS 10.12, *) {
            self.defaultLibrary = try? device.makeDefaultLibrary(bundle: Bundle.main)
        } else {
            self.defaultLibrary = device.makeDefaultLibrary()
        }
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
        
        // This #available block for makeLibrary(URL:) is now redundant due to newLibrary(URL:) above.
        // However, keeping it doesn't hurt as newLibrary should be preferred.
        // If newLibrary failed, this would also likely fail or not be reached.
        if #available(macOS 10.13, iOS 11.0, *) { // Guard for URL(string:) which is not the primary concern here
            // URL(string: libraryFileOrPath) might be problematic if libraryFileOrPath is not a valid URL string
            // but URL(fileURLWithPath:) is safer. The previous newLibrary(URL: fileURL) should cover this.
            // For safety, let's assume fileURL is the correct one to use if we were to keep this block.
            if let library = try? device.newLibrary(URL: fileURL) { // Changed to newLibrary for consistency
                return library
            }
        }
        
        return nil
    }
    
    static func readMTLFunction(_ name: String) async throws -> MTLFunction {
        let sharedDevice = await Shared.shared.getInitializedDevice()
        // First read the project
        if let libray = sharedDevice.defaultLibrary, let function = libray.makeFunction(name: name) {
            return function
        }
        // Then read from ``Harbeth Framework``
        if let libray = sharedDevice.harbethLibrary, let function = libray.makeFunction(name: name) {
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
    
    public static func device() async -> MTLDevice {
        let d = await Shared.shared.getInitializedDevice()
        return d.device
    }
    
    public static func colorSpace() async -> CGColorSpace {
        let d = await Shared.shared.getInitializedDevice()
        return d.colorSpace
    }
    
    public static func bitmapInfo() -> UInt32 {
        // You can't get `CGImage.bitmapInfo` here, otherwise the heic and heif formats will turn blue.
        // Fixed draw bitmap after applying filter image color rgba => bgra.
        // See：https://github.com/yangKJ/Harbeth/issues/12
        return CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    }
    
    public static func commandQueue() async -> MTLCommandQueue {
        let d = await Shared.shared.getInitializedDevice()
        return d.commandQueue
    }
    
    public static func sharedTextureCache() async -> CVMetalTextureCache? {
        let d = await Shared.shared.getInitializedDevice()
        return await d.getTextureCache()
    }
    
    public static func context() async -> CIContext {
        return await Device.context(colorSpace: await Device.colorSpace())
    }
    
    public static func context(cgImage: CGImage) async -> CIContext {
        let cs = cgImage.colorSpace ?? (await Device.colorSpace())
        return await Device.context(colorSpace: cs)
    }
    
    public static func context(colorSpace: CGColorSpace) async -> CIContext {
        let sharedDevice = await Shared.shared.getInitializedDevice()
        if let context = sharedDevice.contexts[colorSpace] {
            return context
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
        if #available(iOS 13.0, macOS 10.12, *) {
            // This option is undocumented, possibly only effective on iOS?
            // Sounds more like allowLowPerformance, though, so turn it off
            options[CIContextOption.allowLowPower] = false
        }
        if let workingColorSpace = sharedDevice.workingColorSpace {
            // We are likely to encounter images with wider colour than sRGB
            options[CIContextOption.workingColorSpace] = workingColorSpace
        }
        let context: CIContext
        // Updated to await async versions of commandQueue() and device()
        if #available(iOS 13.0, *, macOS 10.15, *) {
            context = CIContext(mtlCommandQueue: await Device.commandQueue(), options: options)
        } else if #available(iOS 9.0, *, macOS 10.11, *) {
            context = CIContext(mtlDevice: await Device.device(), options: options)
        } else {
            context = CIContext(options: options)
        }
        sharedDevice.contexts[colorSpace] = context // Mutating actor's property via reference
        return context
    }
}
