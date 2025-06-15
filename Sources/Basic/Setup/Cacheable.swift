@preconcurrency import Metal
//
//  TextureCacheable.swift
//  Harbeth
//
//  Created by Condy on 2022/10/28.
//

import Foundation
import ObjectiveC
import CoreVideo

// For simulator compile
#if targetEnvironment(simulator)
public typealias CVMetalTexture = AnyClass
public typealias CVMetalTextureCache = AnyClass
#endif

public protocol Cacheable: AnyObject {
    
    /// Release the CVMetalTextureCache resource
    func deferTextureCache()
}

// fileprivate let C7ATCacheContext: UInt8 = 0
// fileprivate let textureCacheKey = UnsafeRawPointer(bitPattern: Int(C7ATCacheContext) + 1)!
private enum AssociatedKeys {
    static let textureCache = "harbeth.textureCacheKey"
}

extension Cacheable {
    
    public func deferTextureCache() {
        let existingCache = synchronizedCacheable { // Keep sync access for defer
            if let object = objc_getAssociatedObject(self, AssociatedKeys.textureCache) {
                return object as! CVMetalTextureCache // Warning suggests this cast will succeed if object is non-nil
            }
            return nil
        }
        #if !targetEnvironment(simulator)
        if let textureCache = existingCache {
            CVMetalTextureCacheFlush(textureCache, 0)
        }
        #endif
        // Optional: remove the associated object after flushing if it's a true "defer"
        // synchronizedCacheable {
        //     objc_setAssociatedObject(self, textureCacheKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        // }
    }
    
    private func synchronizedCacheable<T>( _ action: () -> T) -> T {
        objc_sync_enter(self)
        let result = action()
        objc_sync_exit(self)
        return result
    }
}
