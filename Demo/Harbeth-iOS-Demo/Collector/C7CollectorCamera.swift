//
//  C7CollectorCamera.swift
//  Harbeth
//
//  Created by Condy on 2022/2/25.
//

import Foundation
import AVFoundation
import Harbeth

// Note: @unchecked Sendable is used because C7CollectorCamera manages AVFoundation objects (like AVCaptureSession)
// and uses specific dispatch queues for synchronization. Its safe concurrent use relies on this internal queue management
// rather than full Sendable conformance of all its properties, especially due to synchronous delegate requirements.
public final class C7CollectorCamera: C7Collector, @unchecked Sendable {
    
    private let sessionQueue = DispatchQueue(label: "camera.session.collector.metal")
    private let bufferQueue  = DispatchQueue(label: "camera.collector.buffer.metal")
    
    public var deviceInput: AVCaptureDeviceInput? {
        didSet {
            if let oldValue = oldValue {
                self.captureSession.removeInput(oldValue)
            }
            if let input = self.deviceInput {
                self.captureSession.addInput(input)
            }
        }
    }
    
    public lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        let preset = AVCaptureSession.Preset.hd1280x720
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }
        return session
    }()
    
    public lazy var videoOutput: AVCaptureVideoDataOutput = {
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = videoSettings
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: bufferQueue)
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }
        if let connection = output.connection(with: .video) {
            let desiredRotationAngle: CGFloat = 90 // For portrait
            if connection.isVideoRotationAngleSupported(desiredRotationAngle) {
                connection.videoRotationAngle = desiredRotationAngle
            }
        }
        return output
    }()
    
    deinit {
        self.stopRunning()
        self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
    }
    
    public override func setupInit() {
        super.setupInit()
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        guard let camera = AVCaptureDevice.default(for: .video) else { return }
        self.deviceInput = try? AVCaptureDeviceInput(device: camera)
        captureSession.beginConfiguration()
        let _ = self.videoOutput
        captureSession.commitConfiguration()
    }
}

extension C7CollectorCamera {
    
    public func startRunning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.startRunning()
        }
    }
    
    public func stopRunning() {
        if self.captureSession.isRunning {
            self.captureSession.stopRunning()
        }
    }
}

extension C7CollectorCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        self.processing(with: pixelBuffer)
    }
}
