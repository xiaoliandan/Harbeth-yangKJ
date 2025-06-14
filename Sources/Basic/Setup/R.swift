//
//  R.swift
//  Harbeth
//
//  Created by Condy on 2022/10/19.
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

fileprivate actor RCacheActor {
    static let shared = RCacheActor()
    private var cacheBundles = [String: Bundle]()

    private init() { } // Private initializer for singleton pattern

    func frameworkBundle(named bundleName: String, forClassInBundle classInBundle: AnyClass, appBundle: Bundle) -> Bundle? {
        if let bundle = cacheBundles[bundleName] {
            return bundle
        }

        let bundleForClass = Bundle(for: classInBundle)
        let candidates = [
            Bundle.main.resourceURL,
            appBundle.resourceURL,
            bundleForClass.resourceURL,
            Bundle.main.bundleURL,
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                cacheBundles[bundleName] = bundle // Actor state mutation
                return bundle
            }
        }
        cacheBundles[bundleName] = bundleForClass // Actor state mutation
        return bundleForClass
    }
}

public struct AnySendableTarget: Sendable {}

/// 资源文件读取
public struct R {
    
    /// Returns the current app's bundle whether it's called from the app or an app extension.
    public static let app: Bundle = {
        var components = Bundle.main.bundleURL.path.split(separator: "/")
        guard let index = (components.lastIndex { $0.hasSuffix(".app") }) else {
            return Bundle.main
        }
        components.removeLast((components.count - 1) - index)
        return Bundle(path: components.joined(separator: "/")) ?? Bundle.main
    }()
    
    // Old cache mechanism removed.
    
    /// Read image resources
    public static func image(_ named: String, forResource: String = "Harbeth") async -> C7Image? {
        let readImageblock = { (bundle: Bundle) -> C7Image? in
            #if os(iOS) || os(tvOS) || os(watchOS)
            return C7Image(named: named, in: bundle, compatibleWith: nil)
            #elseif os(macOS)
            return bundle.image(forResource: named)
            #else
            return nil
            #endif
        }
        if let image = readImageblock(Bundle.main) {
            return image
        }
        guard let bundle = await readFrameworkBundle(with: forResource) else {
            return C7Image.init(named: named) // Assuming this fallback is acceptable
        }
        return readImageblock(bundle)
    }
    
    /// Read color resource
    @available(iOS 11.0, macOS 10.13, *)
    public static func color(_ named: String, forResource: String = "Harbeth") async -> C7Color? {
        let readColorblock = { (bundle: Bundle) -> C7Color? in
            #if os(iOS) || os(tvOS) || os(watchOS)
            return C7Color.init(named: named, in: bundle, compatibleWith: nil)
            #elseif os(macOS)
            return C7Color.init(named: named, bundle: bundle)
            #else
            return nil
            #endif
        }
        if let color = readColorblock(Bundle.main) {
            return color
        }
        guard let bundle = await readFrameworkBundle(with: forResource) else {
            return C7Color.init(named: named) // Assuming this fallback is acceptable
        }
        return readColorblock(bundle)
    }
    
    public static func readFrameworkBundle(with bundleName: String) async -> Bundle? {
        return await RCacheActor.shared.frameworkBundle(named: bundleName, forClassInBundle: R__.self, appBundle: R.app)
    }
}

fileprivate final class R__ { }

extension R {
    
    public static let iRange: ParameterRange<Float, AnySendableTarget> = .init(min: 0.0, max: 1.0, value: 1.0)
    /// 强度范围
    /// Intensity range, used to adjust the mixing ratio of filters and sources.
    public static let intensityRange = iRange
    
    /// Screen window width.
    @MainActor public static var width: CGFloat {
        #if canImport(UIKit)
        return UIScreen.main.bounds.width
        #elseif os(macOS)
        return NSScreen.main?.visibleFrame.width ?? 0.0
        #else
        return 0.0
        #endif
    }
    
    /// Screen window height.
    @MainActor public static var height: CGFloat {
        #if canImport(UIKit)
        return UIScreen.main.bounds.height
        #elseif os(macOS)
        return NSScreen.main?.visibleFrame.height ?? 0.0
        #else
        return 0.0
        #endif
    }
}
