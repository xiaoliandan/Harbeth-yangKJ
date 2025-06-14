//
//  CameraViewController.swift
//  MetalDemo
//
//  Created by Condy on 2022/2/25.
//

import Harbeth

class CameraViewController: UIViewController {
    
    var tuple: FilterResult?
    
    lazy var originImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = UIColor.background2?.withAlphaComponent(0.3)
        imageView.frame = self.view.frame
        return imageView
    }()
    
    lazy var camera: C7CollectorCamera = {
        let camera = C7CollectorCamera.init(delegate: self)
        camera.captureSession.sessionPreset = AVCaptureSession.Preset.hd1280x720
        camera.filters = [self.tuple!.filter]
        return camera
    }()
    
    deinit {
        print("CameraViewController is deinit.")
        Shared.shared.deinitDevice()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        camera.startRunning()
    }
    
    func setupUI() {
        view.backgroundColor = UIColor.background
        view.addSubview(originImageView)
    }
}

extension CameraViewController: C7CollectorImageDelegate {
    
    nonisolated func preview(_ collector: C7Collector, fliter image: C7Image) {
        Task { @MainActor in
            self.originImageView.image = image
        }
    }
    
    nonisolated func captureOutput(_ collector: C7Collector, pixelBuffer: CVPixelBuffer) {
        
    }
    
    nonisolated func captureOutput(_ collector: C7Collector, texture: MTLTexture) {
        
    }
}
