//
//  HomeViewModel.swift
//  MetalQueen
//
//  Created by Condy on 2021/8/7.
//

import Foundation
import UIKit

enum ViewType {
    case image, camera, player
}

struct HomeViewModel {
    var viewType: ViewType
    
    func setupViewController(_ type: ViewControllerType) -> UIViewController {
        switch viewType {
        case .image:
            let vc = ImageViewController()
            let tuple = type.setupFilterObject()
            vc.filter = tuple.filter
            vc.callback = tuple.callback
            if let maxmin = tuple.maxminValue {
                vc.slider.minimumValue = maxmin.min
                vc.slider.maximumValue = maxmin.max
                vc.slider.value = maxmin.current
            } else {
                vc.slider.isHidden = true
            }
            vc.originImage = type.image
            return vc
        case .camera:
            let vc = CameraViewController()
            vc.tuple = type.setupFilterObject()
            return vc
        case .player:
            let vc = PlayerViewController()
            vc.tuple = type.setupFilterObject()
            return vc
        }
    }
    
    lazy var datas: [String: [ViewControllerType]] = {
        switch viewType {
        case .image, .player:
            return [
                "CImage": coreImage,
                "查找滤镜": lookup,
                "效果展示": effect,
                "颜色处理": color,
                "形状变化": shape,
                "模糊处理": blur,
                "图片融合": blend,
                "矩阵卷积": matrix,
            ]
        case .camera:
            var filters = color
            filters.insert(.Storyboard, at: 0)
            filters.insert(.Rotate, at: 1)
            filters.insert(.Flip, at: 2)
            return ["相机特效 - 真机测试": filters]
        }
    }()
    
    let visual: [ViewControllerType] = [
        .ShiftGlitch, .SoulOut, .EdgeGlow,
        .Luminance, .ColorMatrix4x4, .Monochrome,
        .VoronoiOverlay, .Storyboard,
    ]
    
    let effect: [ViewControllerType] = [
        .TextHEIC, .ZoomBlur, .Vignette, .WaterRipple,
        .Pixellated, .Crosshatch, .GlassSphere,
        .Bulge, .Pinch, .PolkaDot,
        .Posterize, .Swirl, .SplitScreen, .Storyboard,
        .Monochrome, .ReplaceColor, .ChromaKey,
        .VoronoiOverlay,
    ]
    
    let color: [ViewControllerType] = [
        .Opacity, .Exposure, .Luminance,
        .Hue, .Contrast, .HighlightShadow,
        .Saturation, .WhiteBalance, .Vibrance,
        .Granularity, .Levels, .Sobel,
        .ChannelRGBA, .FalseColor, .ColorInvert,
        .Grayed, .Color2Gray, .Color2BGRA, .Color2BRGA,
        .Color2GBRA, .Color2GRBA, .Color2RBGA,
        .ComicStrip, .OilPainting, .Sketch,
    ]
    
    let shape: [ViewControllerType] = [
        .Crop, .Rotate, .Resize, .Flip,
        .Transform,
    ]
    
    let blur: [ViewControllerType] = [
        .MonochromeDilation, .MotionBlur, .MeanBlur,
        .GaussianBlur, .BilateralBlur, .MPSGaussian,
    ]
    
    let blend: [ViewControllerType] = [
        .HueBlend, .AlphaBlend, .LuminosityBlend,
    ]
    
    let lookup: [ViewControllerType] = [
        .abao, .Split,
    ]
    
    let matrix: [ViewControllerType] = [
        .ColorMatrix4x4, .Convolution3x3, .Sharpen3x3,
        .Sepia,
    ]
    
    let coreImage: [ViewControllerType] = [
        .CIHS, .CIGaussian, .ColorMonochrome,
    ]
}
