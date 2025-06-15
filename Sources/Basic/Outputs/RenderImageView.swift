//
//  RenderView.swift
//  Harbeth
//
//  Created by Condy on 2024/3/20.
//

import Foundation
import MetalKit

public final class RenderImageView: C7ImageView, Renderable {
    
    public typealias Element = C7Image
    
    public override var image: C7Image? {
        didSet {
            if lockedSource {
                return
            }
            // self.setupInputSource() // Assuming this remains synchronous
            // Task {
            //    await self.filtering()
            // }
            // New logic for image.didSet:
            Task {
                do {
                    try await self.setupInputSource()
                    await self.filtering()
                } catch {
                    // Optional: Log error
                    print("RenderImageView: Error during setupInputSource or filtering: \(error)")
                }
            }
        }
    }
}

extension Renderable where Self: C7ImageView {
    
    @MainActor public func setupInputSource() async throws {
        if lockedSource {
            return
        }
        if let image = self.image {
            self.inputSource = try await TextureLoader(with: image).texture
        }
    }
    
    @MainActor public func setupOutputDest(_ dest: MTLTexture) {
        // DispatchQueue.main.async {
        if let image = self.image {
            self.lockedSource = true
            self.image = try? dest.c7.fixImageOrientation(refImage: image)
            self.lockedSource = false
        }
        // }
    }
}
