//
//  ImageViewController.swift
//  MetalQueen
//
//  Created by Condy on 2021/8/7.
//

import Harbeth

class ImageViewController: UIViewController {
    
    var filter: C7FilterProtocol?
    var callback: FilterCallback?
    var originImage: UIImage!
    weak var timer: Timer?
    private var timerShouldAddValue: Bool = true
    lazy var autoBarButton: UIBarButtonItem = {
        let barButton = UIBarButtonItem(title: "Auto",
                                        style: .plain,
                                        target: self,
                                        action: #selector(autoTestAction))
        return barButton
    }()
    
    lazy var slider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action:#selector(sliderDidchange(_:)), for: .valueChanged)
        return slider
    }()
    
    lazy var originImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.borderColor = UIColor.background2?.cgColor
        imageView.layer.borderWidth = 0.5
        return imageView
    }()
    
    lazy var renderView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.borderColor = UIColor.background2?.cgColor
        imageView.layer.borderWidth = 0.5
        return imageView
    }()
    
    lazy var leftLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = UIColor.background2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    lazy var rightLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .right
        label.textColor = UIColor.background2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    lazy var currentLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = UIColor.background2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    deinit {
        print("ImageViewController is Deinit.")
        Shared.shared.deinitDevice()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFilter()
    }
    
    func setupUI() {
        navigationItem.rightBarButtonItem = autoBarButton
        view.backgroundColor = UIColor.background
        view.addSubview(originImageView)
        view.addSubview(renderView)
        view.addSubview(slider)
        view.addSubview(leftLabel)
        view.addSubview(rightLabel)
        view.addSubview(currentLabel)
        NSLayoutConstraint.activate([
            originImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 100),
            renderView.topAnchor.constraint(equalTo: originImageView.bottomAnchor, constant: 15),
            renderView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            renderView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            leftLabel.topAnchor.constraint(equalTo: renderView.bottomAnchor, constant: 20),
            leftLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            leftLabel.widthAnchor.constraint(equalToConstant: 100),
            leftLabel.heightAnchor.constraint(equalToConstant: 30),
            rightLabel.topAnchor.constraint(equalTo: renderView.bottomAnchor, constant: 20),
            rightLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            rightLabel.widthAnchor.constraint(equalToConstant: 100),
            rightLabel.heightAnchor.constraint(equalToConstant: 30),
            currentLabel.topAnchor.constraint(equalTo: renderView.bottomAnchor, constant: 20),
            currentLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            currentLabel.widthAnchor.constraint(equalToConstant: 100),
            currentLabel.heightAnchor.constraint(equalToConstant: 30),
            slider.topAnchor.constraint(equalTo: leftLabel.bottomAnchor, constant: 20),
            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            slider.heightAnchor.constraint(equalToConstant: 30),
        ])
        if slider.isHidden {
            NSLayoutConstraint.activate([
                renderView.heightAnchor.constraint(equalTo: renderView.widthAnchor, multiplier: 3/4),
                originImageView.centerXAnchor.constraint(equalTo: renderView.centerXAnchor),
                originImageView.widthAnchor.constraint(equalTo: renderView.widthAnchor),
                originImageView.heightAnchor.constraint(equalTo: renderView.heightAnchor),
            ])
        } else {
            originImageView.layer.borderWidth = 0
            NSLayoutConstraint.activate([
                renderView.heightAnchor.constraint(equalTo: renderView.widthAnchor, multiplier: 3.5/4),
                originImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
                originImageView.widthAnchor.constraint(equalToConstant: 100),
                originImageView.heightAnchor.constraint(equalToConstant: 100),
            ])
        }
        let bg = UIColor.background2?.withAlphaComponent(0.3)
        originImageView.backgroundColor = bg
        renderView.backgroundColor = bg
        leftLabel.backgroundColor = bg
        rightLabel.backgroundColor = bg
        currentLabel.backgroundColor = bg
        leftLabel.text  = "\(slider.minimumValue)"
        rightLabel.text = "\(slider.maximumValue)"
        currentLabel.text = "\(slider.value)"
        renderView.image = originImage
        originImageView.image = originImage
        leftLabel.isHidden = slider.isHidden
        rightLabel.isHidden = slider.isHidden
        currentLabel.isHidden = slider.isHidden
    }
}

// MARK: - filter process
extension ImageViewController {
    func setupFilter() {
        if slider.isHidden {
            self.asynchronousProcessingImage(with: filter)
            return
        }
        autoTestAction()
    }
    
    @objc func autoTestAction() {
        if slider.isHidden { return }
        
        if let existingTimer = self.timer {
            autoBarButton.title = "Auto"
            existingTimer.invalidate()
            self.timer = nil
        } else {
            autoBarButton.title = "Stop"
            if self.slider.value >= self.slider.maximumValue {
                self.timerShouldAddValue = false
            } else if self.slider.value <= self.slider.minimumValue {
                self.timerShouldAddValue = true
            }

            let newTimer = Timer(timeInterval: 0.025, repeats: true, block: { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }

                    if self.slider.value >= self.slider.maximumValue {
                        self.timerShouldAddValue = false
                    } else if self.slider.value <= self.slider.minimumValue {
                        self.timerShouldAddValue = true
                    }

                    let step = (self.slider.maximumValue - self.slider.minimumValue) / 77
                    if self.timerShouldAddValue {
                        self.slider.value += step
                    } else {
                        self.slider.value -= step
                    }
                    // Clamp slider value
                    self.slider.value = max(self.slider.minimumValue, min(self.slider.value, self.slider.maximumValue))

                    self.currentLabel.text = String(format: "%.2f", self.slider.value)
                    let filter = self.callback?(self.slider.value)
                    self.asynchronousProcessingImage(with: filter)
                }
            })
            RunLoop.main.add(newTimer, forMode: .common)
            newTimer.fire()
            self.timer = newTimer
        }
    }
    
    @objc func sliderDidchange(_ slider: UISlider) {
        self.currentLabel.text = String(format: "%.2f", slider.value)
        let filter = self.callback?(slider.value)
        self.asynchronousProcessingImage(with: filter)
    }
    
    /// 异步处理图像
    func asynchronousProcessingImage(with filter: C7FilterProtocol?) {
        guard let filter = filter else {
            return
        }
        let dest = HarbethIO(element: originImage, filter: filter)
        dest.transmitOutput { [weak self] image in
            DispatchQueue.main.async {
                self?.renderView.image = image
            }
        }
    }
}
