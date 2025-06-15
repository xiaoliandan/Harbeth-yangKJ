@preconcurrency import Metal
//
//  Renderable.swift
//  Harbeth
//
//  Created by Condy on 2024/3/20.
//

import Foundation
import ObjectiveC
import MetalKit

public protocol Renderable: AnyObject {
    associatedtype Element
    
    var filters: [C7FilterProtocol] { get set }
    
    var keepAroundForSynchronousRender: Bool { get set }
    
    /// Frequent changes require this to be set to true.
    var transmitOutputRealTimeCommit: Bool { get set }
    
    var inputSource: MTLTexture? { get set }
    
    func setupInputSource()
    
    func filtering() async

    func applyFilters() async
    
    func setupOutputDest(_ dest: MTLTexture)
}

fileprivate let C7ATRenderableSetFiltersContext: UInt8 = 1
fileprivate let C7ATRenderableInputSourceContext: UInt8 = 2
fileprivate let C7ATRenderableTransmitOutputRealTimeCommitContext: UInt8 = 3
fileprivate let C7ATRenderableKeepAroundForSynchronousRenderContext: UInt8 = 4

extension Renderable {
    public var filters: [C7FilterProtocol] {
        get {
            return synchronizedRenderable {
                if let object = objc_getAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableSetFiltersContext))!) as? [C7FilterProtocol] {
                    return object
                } else {
                    let object = [C7FilterProtocol]()
                    objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableSetFiltersContext))!, object, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                    return object
                }
            }
        }
        set {
            synchronizedRenderable {
                setupInputSource() // Assuming this remains synchronous
                objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableSetFiltersContext))!, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                // The call to filtering() is removed.
            }
        }
    }
    
    public var keepAroundForSynchronousRender: Bool {
        get {
            return synchronizedRenderable {
                if let object = objc_getAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableKeepAroundForSynchronousRenderContext))!) as? Bool {
                    return object
                } else {
                    objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableKeepAroundForSynchronousRenderContext))!, true, .OBJC_ASSOCIATION_ASSIGN)
                    return true
                }
            }
        }
        set {
            synchronizedRenderable {
                objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableKeepAroundForSynchronousRenderContext))!, newValue, .OBJC_ASSOCIATION_ASSIGN)
            }
        }
    }
    
    public var transmitOutputRealTimeCommit: Bool {
        get {
            return synchronizedRenderable {
                if let object = objc_getAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableTransmitOutputRealTimeCommitContext))!) as? Bool {
                    return object
                } else {
                    objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableTransmitOutputRealTimeCommitContext))!, false, .OBJC_ASSOCIATION_ASSIGN)
                    return false
                }
            }
        }
        set {
            synchronizedRenderable {
                objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableTransmitOutputRealTimeCommitContext))!, newValue, .OBJC_ASSOCIATION_ASSIGN)
            }
        }
    }
    
    public weak var inputSource: MTLTexture? {
        get {
            synchronizedRenderable {
                objc_getAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableInputSourceContext))!) as? MTLTexture
            }
        }
        set {
            synchronizedRenderable {
                objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableInputSourceContext))!, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
    
    @MainActor public func filtering() async {
        guard let texture = inputSource, filters.count > 0 else {
            // If there's no texture or no filters, consider what should happen.
            // Maybe call setupOutputDest with the original inputSource if no filters?
            // Or simply return if there's nothing to process.
            if let texture = inputSource, filters.isEmpty {
                self.setupOutputDest(texture) // Output original texture if no filters
            }
            return
        }
        var dest = HarbethIO(element: texture, filters: filters)
        dest.transmitOutputRealTimeCommit = transmitOutputRealTimeCommit

        if self.keepAroundForSynchronousRender {
            // This mode implies a synchronous expectation which conflicts with `async filtering`.
            // For now, we'll make it async but the name "SynchronousRender" will be misleading.
            // This might need further design review for its purpose in an async world.
            do {
                self.lockedSource = true
                let result = try await dest.output() // Now async
                self.setupOutputDest(result)
                self.lockedSource = false
            } catch {
                print("Error during synchronous-style filtering: \(error)")
                self.lockedSource = false
                return
            }
        } else {
            do {
                self.lockedSource = true
                // Assuming dest.output() is the primary way to get results now.
                let result = try await dest.output()
                self.setupOutputDest(result) // Already on MainActor
                self.lockedSource = false
            } catch {
                // Log error or handle as appropriate
                print("Error during async filtering: \(error)")
                self.lockedSource = false // Ensure lock is released
                return
            }
        }
    }

    @MainActor public func applyFilters() async {
        await self.filtering()
    }
}

fileprivate let C7ATRenderableLockedSourceContext: UInt8 = 5

extension Renderable {
    var lockedSource: Bool {
        get {
            return synchronizedRenderable {
                if let locked = objc_getAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableLockedSourceContext))!) as? Bool {
                    return locked
                } else {
                    objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableLockedSourceContext))!, false, .OBJC_ASSOCIATION_ASSIGN)
                    return false
                }
            }
        }
        set {
            synchronizedRenderable {
                objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: Int(C7ATRenderableLockedSourceContext))!, newValue, .OBJC_ASSOCIATION_ASSIGN)
            }
        }
    }
    
    private func synchronizedRenderable<T>( _ action: () -> T) -> T {
        objc_sync_enter(self)
        let result = action()
        objc_sync_exit(self)
        return result
    }
}
