@preconcurrency import Metal
//
//  RenderView.swift
//  Harbeth
//
//  Created by Condy on 2024/8/1.
//

import Foundation
import MetalKit

#if os(iOS) || os(tvOS) || os(watchOS)
open class RenderView: C7View {
    
    private var metalDevice: MTLDevice!
    private var metalCommandQueue: MTLCommandQueue!
    private var mtkRenderView: MTKView!

    private var displayTexture: MTLTexture?
    private var _isRendering: Bool = false

    private var screenScale: CGFloat = 1.0
    private var backgroundAccessingBounds: CGRect = .zero
    
    // Removed lazy var renderView

    @MainActor public override init(frame frameRect: CGRect) { // UIView inits are @MainActor
        super.init(frame: frameRect)
        // Defer metal setup to an async task to not block init
        Task {
            await self.initializeMetalResources()
            // Potentially redraw if inputTexture is already set
            if self.inputTexture != nil || !self.filters.isEmpty {
                self.setNeedsRedraw()
            }
        }
    }
    
    @MainActor public required init?(coder: NSCoder) {
        super.init(coder: coder)
        Task {
            await self.initializeMetalResources()
            if self.inputTexture != nil || !self.filters.isEmpty {
                self.setNeedsRedraw()
            }
        }
    }

    @MainActor private func initializeMetalResources() async {
        self.metalDevice = await Device.device()
        self.metalCommandQueue = await Device.commandQueue()

        // Initialize renderView here
        let view = MTKView(frame: self.bounds, device: self.metalDevice)
        view.delegate = self
        view.isPaused = true
        view.enableSetNeedsDisplay = false // Default based on original lazy var
        view.contentMode = self.contentMode
        view.framebufferOnly = false
        view.autoResizeDrawable = true
        self.mtkRenderView = view

        // Original setupMTKView logic that adds subview
        if #available(iOS 11.0, *) {
            self.accessibilityIgnoresInvertColors = true
        }
        self.isOpaque = true
        self.addSubview(self.mtkRenderView) // Add the newly created view
    }
    
    public var inputTexture: MTLTexture? {
        didSet {
            self.updateContentScaleFactor()
            self.setNeedsRedraw()
        }
    }
    
    public var filters: [C7FilterProtocol] = [] {
        didSet {
            self.updateContentScaleFactor()
            self.setNeedsRedraw()
        }
    }
    
    public var drawsImmediately: Bool = false {
        didSet {
            if drawsImmediately {
                mtkRenderView?.isPaused = true
                mtkRenderView?.enableSetNeedsDisplay = false
            } else {
                mtkRenderView?.isPaused = true
                mtkRenderView?.enableSetNeedsDisplay = true
            }
        }
    }
    
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        if let screen = self.window?.screen {
            screenScale = min(screen.nativeScale, screen.scale)
        } else {
            screenScale = 1.0
        }
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        // mtkRenderView might not be initialized yet if initializeMetalResources hasn't completed.
        // Add a guard or ensure it's initialized before layoutSubviews can be meaningfully called.
        // For now, we'll assume it should be available or a guard is needed.
        guard let mtkRenderView = self.mtkRenderView else { return }
        mtkRenderView.frame = self.bounds
        self.updateContentScaleFactor()
        self.setNeedsRedraw()
    }
}

extension RenderView {
    
    // Removed setupMTKView()
    
    private func setNeedsRedraw() {
        Task { await self.renderContentAndPrepareDisplay() }
    }

    @MainActor private func renderContentAndPrepareDisplay() async {
        guard !_isRendering else {
            return
        }
        _isRendering = true

        defer {
            _isRendering = false
        }

        guard let texture = self.inputTexture,
              let mtkView = self.mtkRenderView, // Ensure mtkView is available
              self.alpha > 0, !self.isHidden else {
            // Potentially clear displayTexture if input is not valid
            self.displayTexture = nil
            if let mtkView = self.mtkRenderView { mtkView.draw() } // Trigger draw to clear
            return
        }

        // Ensure command queue is available
        guard let commandQueue = self.metalCommandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        var finalTexture: MTLTexture? = texture // Start with input texture

        if !filters.isEmpty {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: mtkView.colorPixelFormat, // Use view's pixel format
                width: mtkView.drawableSize.width > 0 ? Int(mtkView.drawableSize.width) : texture.width,
                height: mtkView.drawableSize.height > 0 ? Int(mtkView.drawableSize.height) : texture.height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget] // Typical usage
            guard let renderTargetTexture = self.metalDevice?.makeTexture(descriptor: descriptor) else {
                print("Failed to create render target texture.")
                return
            }

            var currentProcessingTexture = texture
            //var outputTexture = renderTargetTexture // In a loop, this would be re-assigned.
                                                  // The last filter should write to renderTargetTexture.
                                                  // Earlier filters might need temporary textures if ping-ponging.
                                                  // For simplicity, let's assume filters write to a texture they manage or are given.
                                                  // The final output after all filters is what we care about.

            for (index, filter) in self.filters.enumerated() {
                // Determine destination for this filter pass
                // If it's the last filter, the destination is the main renderTargetTexture.
                // Otherwise, it should be a temporary texture (if not handled by filter internally).
                // This simplified example assumes applyAtTexture can take same input and output (which might be problematic)
                // or that it correctly uses an intermediate if currentProcessingTexture is also the target.
                // A robust solution uses ping-pong textures.
                // Let's assume applyAtTexture is smart enough or we use renderTargetTexture as the final target.

                let iterationDestTexture: MTLTexture
                if index == self.filters.count - 1 {
                    iterationDestTexture = renderTargetTexture
                } else {
                    // Need a temporary texture for intermediate steps if filters can't write to same as input
                    // This is a placeholder for a proper temporary texture strategy
                    let tempDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: currentProcessingTexture.pixelFormat,
                        width: currentProcessingTexture.width,
                        height: currentProcessingTexture.height,
                        mipmapped: false)
                    tempDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
                    guard let tempTex = self.metalDevice?.makeTexture(descriptor: tempDescriptor) else {
                        print("Failed to create temporary processing texture.")
                        self.displayTexture = currentProcessingTexture // Fallback to previous state
                        if let mtkView = self.mtkRenderView { mtkView.draw() }
                        return
                    }
                    iterationDestTexture = tempTex
                }

                let sourceForFilter = try! await filter.combinationBegin(for: commandBuffer, source: currentProcessingTexture, dest: iterationDestTexture)
                var tempResultTexture: MTLTexture?
                switch filter.modifier {
                case .compute, .mps, .render:
                    tempResultTexture = try? await filter.applyAtTexture(form: sourceForFilter, to: iterationDestTexture, for: commandBuffer)
                default:
                    tempResultTexture = sourceForFilter
                    break
                }
                if let result = tempResultTexture {
                    currentProcessingTexture = result
                } else {
                    print("Filter application failed for: \(filter)")
                    currentProcessingTexture = texture // Fallback to original
                    break
                }
                _ = try! filter.combinationAfter(for: commandBuffer, input: currentProcessingTexture, source: texture)
            }
            finalTexture = currentProcessingTexture
        }

        self.displayTexture = finalTexture

        if let mtkView = self.mtkRenderView {
             mtkView.draw()
        }
    }
    
    private func updateContentScaleFactor() {
        guard let mtkRenderView = self.mtkRenderView else { return }
        guard let inputTexture = inputTexture,
              inputTexture.width > 0, inputTexture.height > 0,
              mtkRenderView.frame.width > 0, mtkRenderView.frame.height > 0,
              self.window?.screen != nil else {
            return
        }
        let ws = CGFloat(inputTexture.width) / mtkRenderView.frame.width
        let wh = CGFloat(inputTexture.height) / mtkRenderView.frame.height
        let scale = max(min(max(ws, wh), screenScale), 1.0)
        if abs(mtkRenderView.contentScaleFactor - scale) > 0.00001 {
            mtkRenderView.contentScaleFactor = scale
        }
    }
}

extension RenderView: MTKViewDelegate {
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    public func draw(in view: MTKView) {
        guard let commandQueue = self.metalCommandQueue else {
            //print("RenderView: Metal command queue not initialized in draw(in:).")
            return
        }
        guard let drawable = view.currentDrawable,
              let currentDisplayTexture = self.displayTexture, // Use the pre-rendered texture
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            if let descriptor = view.currentRenderPassDescriptor, // Make descriptor mutable
               let currentDrawableToClear = view.currentDrawable, // Use a different name to avoid conflict if currentDrawable is used later
               let cmdBuff = commandQueue.makeCommandBuffer() {

                descriptor.colorAttachments[0].loadAction = .clear
                descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0) // Clear to transparent black

                // Create and end the encoder
                if let commandEncoder = cmdBuff.makeRenderCommandEncoder(descriptor: descriptor) {
                    commandEncoder.endEncoding()
                } else {
                    print("RenderView: Failed to make command encoder for clearing.")
                    // Potentially commit buffer if needed, though less likely if encoder failed
                }

                cmdBuff.present(currentDrawableToClear)
                cmdBuff.commit()
            }
            return
        }

        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            let origin = MTLOrigin(x: 0, y: 0, z: 0)
            // Ensure sourceSize does not exceed source texture dimensions
            let sourceWidth = min(currentDisplayTexture.width, drawable.texture.width)
            let sourceHeight = min(currentDisplayTexture.height, drawable.texture.height)
            if sourceWidth > 0 && sourceHeight > 0 {
                let sourceSize = MTLSize(width: sourceWidth, height: sourceHeight, depth: currentDisplayTexture.depth)
                 blitEncoder.copy(from: currentDisplayTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: sourceSize,
                                 to: drawable.texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
            }
            blitEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
#endif
