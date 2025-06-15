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
    
    /// Asynchronously gets or creates the Metal texture cache.
    @MainActor func getTextureCache() async -> CVMetalTextureCache?
    
    /// Release the CVMetalTextureCache resource
    func deferTextureCache()
}

// fileprivate let C7ATCacheContext: UInt8 = 0
// fileprivate let textureCacheKey = UnsafeRawPointer(bitPattern: Int(C7ATCacheContext) + 1)!
private enum AssociatedKeys {
    static var textureCache: UInt8 = 0
}

extension Cacheable {

    public func getTextureCache() async -> CVMetalTextureCache? {
        // First, check if the cache already exists using the synchronized block
        let existingCache = synchronizedCacheable {
            objc_getAssociatedObject(self, &AssociatedKeys.textureCache) as? CVMetalTextureCache
        }
        if let cache = existingCache {
            return cache
        }

        // If not, create it. The potentially async part is outside the sync block for fetching.
        var newTextureCache: CVMetalTextureCache?
        #if !targetEnvironment(simulator)
        // Since getTextureCache is now @MainActor, Device.device() which is also @MainActor can be called directly.
        let device = await Device.device()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &newTextureCache)
        #endif

        // Now, associate the new cache, again using the synchronized block
        // This is a critical section to prevent race conditions on setting the associated object.
        return synchronizedCacheable {
            // Re-check in case another thread/task created it in the meantime
            if let alreadySetCache = objc_getAssociatedObject(self, &AssociatedKeys.textureCache) as? CVMetalTextureCache {
                return alreadySetCache // Another task won the race
            }
            objc_setAssociatedObject(self, &AssociatedKeys.textureCache, newTextureCache, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return newTextureCache
        }
    }
    
    public func deferTextureCache() {
        let existingCache = synchronizedCacheable { // Keep sync access for defer
            objc_getAssociatedObject(self, &AssociatedKeys.textureCache) as? CVMetalTextureCache
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
