//
//  C7CollectorVideo.swift
//  ATMetalBand
//
//  Created by Condy on 2022/2/13.
//

import Foundation
import AVFoundation
import Harbeth

// Note: @unchecked Sendable is used because this class manages AVFoundation objects (AVPlayer, AVPlayerItemVideoOutput),
// a CADisplayLink, and interacts with delegate patterns. Thread safety for main-thread
// operations is managed by explicit DispatchQueue.main.async calls.
public final class C7CollectorVideo: C7Collector, @unchecked Sendable {
    
    private var player: AVPlayer!
    public private(set) var videoOutput: AVPlayerItemVideoOutput!
    
    lazy var displayLink: CADisplayLink = {
        let dl = CADisplayLink(target: self, selector: #selector(readBuffer(_:)))
        // Ensure 'add' and initial 'isPaused' state are set on the main thread.
        DispatchQueue.main.async {
            dl.add(to: .main, forMode: .default)
            dl.isPaused = true
        }
        return dl
    }()
    
    public convenience init(player: AVPlayer, delegate: C7CollectorImageDelegate) {
        self.init(delegate: delegate)
        self.player = player
        setupPlayer(player)
    }
    
    public override func setupInit() {
        super.setupInit()
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.setupVideoOutput()
        }
    }
}

extension C7CollectorVideo {
    
    public func play() {
        player.play() // AVPlayer.play() is thread-safe
        DispatchQueue.main.async { [weak self] in
            self?.displayLink.isPaused = false
        }
    }
    
    public func pause() {
        player.pause() // AVPlayer.pause() is thread-safe
        DispatchQueue.main.async { [weak self] in
            self?.displayLink.isPaused = true
        }
    }
}

extension C7CollectorVideo {
    
    func setupPlayer(_ player: AVPlayer) {
        if let currentItem = player.currentItem {
            // videoOutput might be nil here if setupVideoOutput's async block from setupInit hasn't run.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let videoOutput = self.videoOutput {
                    currentItem.add(videoOutput)
                } else {
                    print("C7CollectorVideo: videoOutput not yet initialized in setupPlayer's async block when trying to add to AVPlayerItem.")
                }
            }
        }
    }
    
    func setupVideoOutput() {
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: videoSettings)
    }
    
    @objc func readBuffer(_ sender: CADisplayLink) {
        let time = videoOutput.itemTime(forHostTime: sender.timestamp + sender.duration)
        guard videoOutput.hasNewPixelBuffer(forItemTime: time) else {
            return
        }
        let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        self.processing(with: pixelBuffer)
    }
}
