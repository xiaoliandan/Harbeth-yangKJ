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
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Could not create Metal Device")
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = queue
        
        self.defaultLibrary = try? device.makeDefaultLibrary(bundle: Bundle.main)
        self.harbethLibrary = Device.makeFrameworkLibrary(device, for: "Harbeth")
        
        if defaultLibrary == nil && harbethLibrary == nil {
            HarbethError.failed("Could not load library")
        }
    }
    
    deinit {
        print("Device is deinit.")
    }
}

extension Device {
    
    public static func makeFrameworkLibrary(_ device: MTLDevice, for resource: String) -> MTLLibrary? {
        #if SWIFT_PACKAGE
        /// Fixed the Swift PM cannot read the `.metal` file.
        /// https://stackoverflow.com/questions/63237395/generating-resource-bundle-accessor-type-bundle-has-no-member-module
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            return library
        }
        if let pathURL = Bundle.module.url(forResource: "default", withExtension: "metallib") {
            do {
                let library = try device.makeLibrary(URL: pathURL)
                return library
            } catch {
                HarbethError.failed("Failed to load library: \(error)")
            }
        }
        #endif
        
        /// Fixed the read failure of imported local resources was rectified.
        if let library = try? device.makeDefaultLibrary(bundle: Bundle(for: Device.self)) {
            return library
        }
        
        let bundle = R.readFrameworkBundle(with: resource)
        /// Fixed libraryFile is nil. podspec file `s.static_framework = false`
        /// https://github.com/CocoaPods/CocoaPods/issues/7967
        guard let libraryFile = bundle?.path(forResource: "default", ofType: "metallib") else {
            return nil
        }
        
        do {
            /// Compatible with the Bundle address used by CocoaPods to import framework.
            let library = try device.makeLibrary(URL: URL(fileURLWithPath: libraryFile))
            return library
        } catch {
            HarbethError.failed("Failed to load library: \(error)")
        }
        
        return nil
    }
    
    static func readMTLFunction(_ name: String) throws -> MTLFunction {
        // First read the project
        if let libray = Shared.shared.device?.defaultLibrary, let function = libray.makeFunction(name: name) {
            return function
        }
        // Then read from ``Harbeth Framework``
        if let libray = Shared.shared.device?.harbethLibrary, let function = libray.makeFunction(name: name) {
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
    
    public static func device() -> MTLDevice {
        return Shared.shared.device!.device
    }
    
    public static func colorSpace() -> CGColorSpace {
        // Unitive the color space, otherwise it will crash.
        return Shared.shared.device?.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    }
    
    public static func bitmapInfo() -> UInt32 {
        // You can't get `CGImage.bitmapInfo` here, otherwise the heic and heif formats will turn blue.
        // Fixed draw bitmap after applying filter image color rgba => bgra.
        // See：https://github.com/yangKJ/Harbeth/issues/12
        return CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    }
    
    public static func commandQueue() -> MTLCommandQueue {
        return Shared.shared.device!.commandQueue
    }
    
    public static func sharedTextureCache() -> CVMetalTextureCache? {
        return Shared.shared.device?.textureCache
    }
    
    public static func context() -> CIContext {
        Device.context(colorSpace: Device.colorSpace())
    }
    
    public static func context(cgImage: CGImage) -> CIContext {
        let colorSpace = cgImage.colorSpace ?? Device.colorSpace()
        return Device.context(colorSpace: colorSpace)
    }
    
    public static func context(colorSpace: CGColorSpace) -> CIContext {
        if let context = Shared.shared.device?.contexts[colorSpace] {
            return context
        }
        var options: [CIContextOption : Any] = [
            .outputColorSpace: colorSpace,
            // Caching does provide a minor speed boost without ballooning memory use, so let's have it on
            .cacheIntermediates: true,
            // Low GPU priority would make sense for a background operation that isn't performance-critical,
            // but we are interested in disk-to-display performance
            .priorityRequestLow: false,
            // Definitely no CPU rendering, please
            .useSoftwareRenderer: false,
            // This is the Apple recommendation, see cgImage(using:) above
            .workingFormat: CIFormat.RGBAh,
        ]
        // This option is undocumented, possibly only effective on iOS?
        // Sounds more like allowLowPerformance, though, so turn it off
        options[CIContextOption.allowLowPower] = false
        if let workingColorSpace = Shared.shared.device?.workingColorSpace {
            // We are likely to encounter images with wider colour than sRGB
            options[.workingColorSpace] = workingColorSpace
        }
        
        let context: CIContext
        if #available(macOS 10.15, *) {
            context = CIContext(mtlCommandQueue: Device.commandQueue(), options: options)
        } else {
            context = CIContext(options: options)
        }
        
        Shared.shared.device?.contexts[colorSpace] = context
        return context
    }
}
