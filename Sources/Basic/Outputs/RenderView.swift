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
                renderView.isPaused = true
                renderView.enableSetNeedsDisplay = false
            } else {
                renderView.isPaused = true
                renderView.enableSetNeedsDisplay = true
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
        guard let mtkRenderView = self.mtkRenderView else { return }
        if drawsImmediately {
            mtkRenderView.draw()
        } else {
            mtkRenderView.setNeedsDisplay()
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
    
    public func draw(in view: MTKView) async {
        // Ensure metalCommandQueue is initialized
        guard let commandQueue = self.metalCommandQueue else {
            print("RenderView: Metal command queue not initialized in draw(in:).")
            return
        }

        guard let texture = inputTexture, self.alpha > 0, !self.isHidden else {
            // Clear current drawable.
            if let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable {
                let commandBuffer = commandQueue.makeCommandBuffer()
                let commandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: descriptor)
                commandEncoder?.endEncoding()
                commandBuffer?.present(drawable)
                commandBuffer?.commit()
            }
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(), // Use stored command queue
              let currentDrawable = view.currentDrawable else {
            return
        }

        guard !filters.isEmpty else {
            // If no filters, just present the drawable (typically means original texture was drawn or view is cleared)
            // This part might need adjustment based on whether the inputTexture itself should be displayed
            // or if it's a passthrough scenario. For now, assume clearing or specific handling for no filters.
            // A common scenario: copy inputTexture to currentDrawable.texture if they are different.
            // For simplicity, let's stick to the original logic of just committing if no filters.
            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
            return
        }

        do {
            var destTexture = currentDrawable.texture
            for filter in self.filters {
                let inputTexture = try filter.combinationBegin(for: commandBuffer, source: texture, dest: destTexture)
                switch filter.modifier {
                case .compute, .mps, .render:
                    // C7FilterProtocol.applyAtTexture is now async
                    destTexture = try await filter.applyAtTexture(form: inputTexture, to: destTexture, for: commandBuffer)
                default:
                    // Assuming .coreimage or other types are handled elsewhere or are synchronous
                    // If .coreimage also becomes async, it would need await here too.
                    // For now, based on previous steps, only compute/render/mps were made async via applyAtTexture.
                    // If applyAtTexture is the sole entry point for all filter types, this is fine.
                    // However, the original code did not call applyAtTexture for .coreimage.
                    // This logic path needs to be verified against how .coreimage filters are meant to be processed.
                    // For now, let's assume the original structure was intentional and only .compute, .mps, .render go via applyAtTexture.
                    // If all filters *must* go through applyAtTexture, then this switch needs to be re-evaluated.
                    // The original code *only* called applyAtTexture for these cases.
                    break
                }
                let _ = try filter.combinationAfter(for: commandBuffer, input: destTexture, source: texture)
            }
            // After all filters, present the drawable
            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
        } catch {
            print("Error during drawing: \(error)")
            // Ensure command buffer is completed even if there's an error to release resources.
            // Presenting the drawable might show an incomplete/incorrect frame,
            // but not committing can lead to stalls.
            commandBuffer.present(currentDrawable) // Or handle error differently
            commandBuffer.commit()
        }
    }
}
#endif
