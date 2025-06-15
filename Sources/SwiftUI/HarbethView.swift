//
//  HarbethView.swift
//  Harbeth
//
//  Created by Condy on 2023/12/5.
//

import SwiftUI

@available(*, deprecated, message: "Typo. Use `HarbethView` instead", renamed: "HarbethView")
@available(iOS 18.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public typealias FilterableView<C: View> = HarbethView<C>

@available(iOS 18.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct HarbethView<Content>: View where Content: View {
    
    public typealias Block = (Image) -> Content
    
    @ObservedObject private var source: Published_Source<C7Image>
    @ViewBuilder private var content: Block
    private let harbethInput: HarbethViewInput
    
    /// Create an instance from the provided value.
    /// - Parameters:
    ///   - image: Will deal image.
    ///   - filters: Need add filters.
    ///   - content: Callback a Image.
    ///   - async: Whether to use asynchronous processing, the UI will not be updated in real time.
    public init(image: C7Image, filters: [C7FilterProtocol], @ViewBuilder content: @escaping Block, async: Bool = false) {
        var input = HarbethViewInput(image: image)
        input.asynchronousProcessing = async
        input.filters = filters
        input.placeholder = image
        self.init(input: input, content: content)
    }
    
    /// Create an instance from the provided value.
    /// - Parameters:
    ///   - input: Input source.
    ///   - content: Callback a Image.
    public init(input: HarbethViewInput, @ViewBuilder content: @escaping Block) {
        self.harbethInput = input
        self.content = content
        // Initialize `source` with a placeholder or initial image.
        // The actual processing will happen in `.task`.
        if let placeholder = input.placeholder {
            self.source = Published_Source(placeholder)
        } else if let image = input.texture?.c7.toImage() { // Initial image from texture if available
            self.source = Published_Source(image)
        } else {
            self.source = Published_Source(C7Image()) // Default empty image
        }
    }
    
    private func setup(input: HarbethViewInput) async {
        guard !input.filters.isEmpty, let texture = input.texture else {
            // If no filters or no texture, ensure placeholder is shown or handle appropriately.
            // This might involve setting source.source to input.placeholder if it wasn't already.
            if let placeholder = input.placeholder, self.source.source != placeholder {
                await MainActor.run { self.source.source = placeholder }
            }
            return
        }

        let dest = HarbethIO(element: texture, filters: input.filters)

        // The `asynchronousProcessing` flag's meaning might need to be re-evaluated.
        // Since `dest.output()` is always async now, both paths will behave similarly
        // in terms of awaiting the processing. The flag might influence other logic
        // not present here, or could be deprecated if it no longer serves a distinct purpose.
        if input.asynchronousProcessing {
            do {
                let resultTexture = try await dest.output()
                if let image = resultTexture.c7.toImage() {
                    await MainActor.run {
                        self.source.source = image
                    }
                }
            } catch {
                print("HarbethView: Error in async processing path - \(error)")
                // Optionally, revert to placeholder on error
                if let placeholder = input.placeholder {
                    await MainActor.run { self.source.source = placeholder }
                }
            }
        } else { // This is the old "synchronous" path, now also async
            do {
                let resultTexture = try await dest.output()
                if let image = resultTexture.c7.toImage() {
                    // self.source is @ObservedObject, its properties should be updated on MainActor
                    await MainActor.run {
                        self.source.source = image
                    }
                }
            } catch {
                print("HarbethView: Error in processing path - \(error)")
                // Optionally, revert to placeholder on error
                if let placeholder = input.placeholder {
                    await MainActor.run { self.source.source = placeholder }
                }
            }
        }
    }
    
    public var body: some View {
        self.content(disImage)
            .task {
                await setup(input: self.harbethInput)
            }
    }
    
    public var disImage: Image {
        get {
            Image.init(c7Image: source.source)
        }
    }
}
