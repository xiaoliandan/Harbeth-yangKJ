//
//  C7Collector.swift
//  Harbeth
//
//  Created by Condy on 2022/2/13.
//

import Foundation
import CoreVideo
import Harbeth

@objc public protocol C7CollectorImageDelegate: NSObjectProtocol {
    
    /// The filter image is returned in the child thread.
    ///
    /// - Parameters:
    ///   - collector: collector
    ///   - image: fliter image
    func preview(_ collector: C7Collector, fliter image: C7Image)
    
    /// Capture other relevant information. The child thread returns the result.
    /// - Parameters:
    ///   - collector: Collector
    ///   - pixelBuffer: A CVPixelBuffer object containing the video frame data and additional information about the frame, such as its format and presentation time.
    @objc optional func captureOutput(_ collector: C7Collector, pixelBuffer: CVPixelBuffer)
    
    /// Capture CVPixelBuffer converted to MTLTexture.
    /// - Parameters:
    ///   - collector: Collector
    ///   - texture: CVPixelBuffer => MTLTexture
    @objc optional func captureOutput(_ collector: C7Collector, texture: MTLTexture)
}

// Note: @unchecked Sendable is used because C7Collector is a base class for collectors
// managing potentially non-Sendable resources (AVFoundation, Metal caches) and using
// delegate patterns. Its subclasses often employ specific dispatch queues or other mechanisms
// for managing concurrency, and this annotation reflects that trust.
public class C7Collector: NSObject, Cacheable, @unchecked Sendable {
    
    public var filters: [C7FilterProtocol] = []
    public var videoSettings: [String : Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    /// Whether to enable automatic direction correction of pictures? The default is true.
    public var autoCorrectDirection: Bool = true
    
    weak var delegate: C7CollectorImageDelegate?
    
    public required init(delegate: C7CollectorImageDelegate) {
        self.delegate = delegate
        super.init()
        setupInit()
    }
    
    deinit {
        delegate = nil
        deferTextureCache()
        print("C7Collector is deinit.")
    }
    
    open func setupInit() {
        // Pre-warm the texture cache asynchronously.
        Task {
            let _ = await self.getTextureCache()
        }
    }
}

extension C7Collector {
    
    func pixelBuffer2Image(_ pixelBuffer: CVPixelBuffer?) async -> C7Image? {
        guard let pixelBuffer = pixelBuffer else {
            return nil
        }
        delegate?.captureOutput?(self, pixelBuffer: pixelBuffer)
        // Get texture cache asynchronously
        guard let cache = await getTextureCache(),
              let texture = pixelBuffer.c7.toMTLTexture(textureCache: cache) else {
            return nil
        }
        let dest = HarbethIO(element: texture, filters: filters)
        // dest.output() is now async
        guard let outputTexture = try? await dest.output() else {
            return nil
        }
        delegate?.captureOutput?(self, texture: outputTexture)
        return outputTexture.c7.toImage()
    }
    
    func processing(with pixelBuffer: CVPixelBuffer?) async {
        guard let pixelBuffer = pixelBuffer else {
            return
        }
        delegate?.captureOutput?(self, pixelBuffer: pixelBuffer)
        // Get texture cache asynchronously
        guard let cache = await getTextureCache(),
              let texture = pixelBuffer.c7.toMTLTexture(textureCache: cache) else {
            return
        }

        var dest = HarbethIO(element: texture, filters: filters)
        dest.transmitOutputRealTimeCommit = true // This property might need re-evaluation with fully async pipeline

        do {
            let desTexture = try await dest.output() // Use the new async output method
            self.delegate?.captureOutput?(self, texture: desTexture)
            guard var image = desTexture.c7.toImage() else {
                return
            }
            if self.autoCorrectDirection {
                image = image.c7.fixOrientation()
            }
            // Switch to main actor for UI updates if delegate methods require it
            // Assuming delegate methods are designed to be called from any thread initially,
            // but UI updates must be on main.
            await MainActor.run {
                self.delegate?.preview(self, fliter: image)
            }
        } catch {
            // Handle or log error from dest.output()
            print("Error processing texture: \(error)")
        }
    }
}
