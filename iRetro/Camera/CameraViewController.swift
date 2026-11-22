//
//  CameraViewController.swift
//  iRetro
//
//  Deployment Target: iOS 12.0+ (Must support iPhone 5S / Apple A7 / 1GB RAM)
//  Frameworks: UIKit, AVFoundation, CoreImage, Metal, MetalKit, Photos, MobileCoreServices
//  Focus: Photo-Only Retro Digicam & Film Simulation (Strictly NO Video Recording)
//

import UIKit
import AVFoundation
import CoreImage
import Metal
import MetalKit
import Photos
import MobileCoreServices

// MARK: - GPU-Accelerated Metal Live Preview View

/// Subclass `MTKView` yang merender `CIImage` pada 30fps secara hemat memori (zero texture leak).
public final class MetalPreviewView: MTKView, MTKViewDelegate {

    private let commandQueue: MTLCommandQueue?
    public let ciContext: CIContext?
    private let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private let imageLock = NSLock()
    private var currentImage: CIImage?

    /// Semaphore dengan kapasitas 1 untuk memastikan GPU A7 tidak pernah menumpuk >1 drawable di memori.
    private let inFlightSemaphore = DispatchSemaphore(value: 1)

    public init(frame: CGRect) {
        let metalDevice = MTLCreateSystemDefaultDevice()
        self.commandQueue = metalDevice?.makeCommandQueue()

        if let device = metalDevice {
            // Matikan cacheIntermediates agar CoreImage tidak menimbun tekstur di RAM 1 GB
            self.ciContext = CIContext(mtlDevice: device, options: [
                CIContextOption.workingColorSpace: colorSpace,
                CIContextOption.cacheIntermediates: false,
                CIContextOption.priorityRequestLow: false
            ])
        } else {
            self.ciContext = nil
        }

        super.init(frame: frame, device: metalDevice)

        self.delegate = self
        self.framebufferOnly = false
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColorMake(0.05, 0.05, 0.05, 1.0)
        // On-demand rendering: hanya menggambar ketika frame kamera baru tiba (30fps)
        self.isPaused = true
        self.enableSetNeedsDisplay = false
        self.contentMode = .scaleAspectFill
        self.clipsToBounds = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported. Use programmatic initialization.")
    }

    /// Menerima `CIImage` yang telah difilter dari thread kamera dan memicu render Metal jika GPU siap.
    public func render(image: CIImage) {
        // Jika GPU masih sibuk menggambar frame sebelumnya, drop frame ini agar tetap 0-lag & hemat RAM
        guard inFlightSemaphore.wait(timeout: .now()) == .success else {
            return
        }

        imageLock.lock()
        self.currentImage = image
        imageLock.unlock()

        self.draw()
    }

    public func flushMemory() {
        imageLock.lock()
        self.currentImage = nil
        imageLock.unlock()
        self.ciContext?.clearCaches()
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        defer {
            inFlightSemaphore.signal()
        }

        autoreleasepool {
            imageLock.lock()
            let imageToRender = self.currentImage
            // Segera lepaskan referensi agar buffer CVPixelBuffer dikembalikan ke pool kamera
            self.currentImage = nil
            imageLock.unlock()

            guard let image = imageToRender,
                  let commandQueue = self.commandQueue,
                  let ciContext = self.ciContext,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let drawable = self.currentDrawable else {
                return
            }

            let drawableBounds = CGRect(origin: .zero, size: self.drawableSize)
            guard drawableBounds.width > 0, drawableBounds.height > 0 else { return }

            // Hitung transformasi Aspect-Fill ke dalam viewfinder 4:3
            let sourceExtent = image.extent
            let scaleX = drawableBounds.width / sourceExtent.width
            let scaleY = drawableBounds.height / sourceExtent.height
            let scale = max(scaleX, scaleY)

            let scaledWidth = sourceExtent.width * scale
            let scaledHeight = sourceExtent.height * scale
            let offsetX = (drawableBounds.width - scaledWidth) * 0.5 - (sourceExtent.origin.x * scale)
            let offsetY = (drawableBounds.height - scaledHeight) * 0.5 - (sourceExtent.origin.y * scale)

            let transformedImage = image
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

            ciContext.render(
                transformedImage,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: drawableBounds,
                colorSpace: colorSpace
            )

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

// MARK: - Retro Digicam Preset Carousel Cell

public final class PresetCollectionViewCell: UICollectionViewCell {
    public static let reuseIdentifier = "PresetCollectionViewCell"

    private let containerView = UIView()
    private let colorStripView = UIView()
    private let codeLabel = UILabel()
    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }

    private func setupViews() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor(white: 0.13, alpha: 1.0)
        containerView.layer.cornerRadius = 6
        containerView.layer.borderWidth = 1.5
        containerView.layer.borderColor = UIColor(white: 0.25, alpha: 1.0).cgColor
        containerView.clipsToBounds = true
        contentView.addSubview(containerView)

        colorStripView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(colorStripView)

        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        codeLabel.font = UIFont(name: "Menlo-Bold", size: 13) ?? UIFont.boldSystemFont(ofSize: 13)
        codeLabel.textColor = UIColor(white: 0.95, alpha: 1.0)
        codeLabel.textAlignment = .center
        containerView.addSubview(codeLabel)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont(name: "Menlo", size: 9) ?? UIFont.systemFont(ofSize: 9)
        nameLabel.textColor = UIColor(white: 0.70, alpha: 1.0)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        containerView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            colorStripView.topAnchor.constraint(equalTo: containerView.topAnchor),
            colorStripView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            colorStripView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            colorStripView.heightAnchor.constraint(equalToConstant: 5),

            codeLabel.topAnchor.constraint(equalTo: colorStripView.bottomAnchor, constant: 6),
            codeLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            codeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),

            nameLabel.topAnchor.constraint(equalTo: codeLabel.bottomAnchor, constant: 2),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -4)
        ])
    }

    public func configure(with preset: FilmPreset, isSelected: Bool) {
        colorStripView.backgroundColor = preset.accentColor
        codeLabel.text = preset.shortCode
        nameLabel.text = preset.name

        if isSelected {
            containerView.backgroundColor = UIColor(white: 0.20, alpha: 1.0)
            containerView.layer.borderColor = UIColor(red: 0.96, green: 0.78, blue: 0.26, alpha: 1.0).cgColor
            codeLabel.textColor = UIColor(red: 0.96, green: 0.78, blue: 0.26, alpha: 1.0)
        } else {
            containerView.backgroundColor = UIColor(white: 0.13, alpha: 1.0)
            containerView.layer.borderColor = UIColor(white: 0.25, alpha: 1.0).cgColor
            codeLabel.textColor = UIColor(white: 0.95, alpha: 1.0)
        }
    }
}

// MARK: - Main Camera View Controller (Photo-Only)

public final class CameraViewController: UIViewController {

    // MARK: - Camera & Rendering Properties

    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    private let sessionQueue = DispatchQueue(label: "com.iretro.camera.session", qos: .userInitiated)
    private let videoOutputQueue = DispatchQueue(label: "com.iretro.camera.videoOutput", qos: .userInteractive)

    private var isSessionConfigured = false
    private var isCapturingPhoto = false

    private let filterLock = NSLock()
    private var activePreviewFilter: CIFilter?
    private var selectedPresetIndex: Int = 0

    // MARK: - UI Components

    private let topBarView = UIView()
    private let modeBadgeLabel = UILabel()
    private let activePresetLabel = UILabel()
    private let importCubeButton = UIButton(type: .system)

    private let viewfinderContainer = UIView()
    private var metalPreviewView: MetalPreviewView!
    private let flashOverlayView = UIView()
    private let gridOverlayView = UIView()

    private let controlsContainer = UIView()
    private var presetCollectionView: UICollectionView!
    private let shutterOuterRing = UIView()
    private let shutterButton = UIButton(type: .custom)
    private let statusToastLabel = UILabel()

    // MARK: - Lifecycle

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override public var prefersStatusBarHidden: Bool {
        return true
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)

        setupRetroDigicamUI()
        applyInitialPreset()
        registerLifecycleNotifications()
        checkCameraPermissionsAndConfigure()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCameraSessionIfNeeded()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCameraSession()
    }

    override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Bersihkan cache tekstur CoreImage pada perangkat 1 GB RAM (iPhone 5S)
        metalPreviewView?.flushMemory()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Active Filter Management

    private func applyInitialPreset() {
        guard !PresetManager.shared.presets.isEmpty else { return }
        selectPreset(at: 0)
    }

    private func selectPreset(at index: Int) {
        let presets = PresetManager.shared.presets
        guard presets.indices.contains(index) else { return }

        selectedPresetIndex = index
        let preset = presets[index]
        let newFilter = preset.makeFilter()

        filterLock.lock()
        activePreviewFilter = newFilter
        filterLock.unlock()

        activePresetLabel.text = "FILM: \(preset.name.uppercased())"
        presetCollectionView.reloadData()
    }

    // MARK: - Camera Setup (Photo-Only, 30fps Lock)

    private func checkCameraPermissionsAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [weak self] in
                self?.configureCaptureSession()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.sessionQueue.async {
                        self.configureCaptureSession()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showPermissionAlert(message: "Akses kamera diperlukan untuk memotret dengan i-Retro.")
                    }
                }
            }
        default:
            showPermissionAlert(message: "Aktifkan izin Kamera di Pengaturan iOS untuk menggunakan i-Retro.")
        }
    }

    private func configureCaptureSession() {
        guard !isSessionConfigured else { return }

        captureSession.beginConfiguration()
        // Preset .photo mendukung pengambilan foto resolusi penuh sekaligus live preview
        if captureSession.canSetSessionPreset(.photo) {
            captureSession.sessionPreset = .photo
        }

        // 1. Rear Camera Input (Photo-Only: tanpa mikrofon / audio input)
        guard let rearCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video) else {
            captureSession.commitConfiguration()
            return
        }

        do {
            let cameraInput = try AVCaptureDeviceInput(device: rearCamera)
            if captureSession.canAddInput(cameraInput) {
                captureSession.addInput(cameraInput)
            }

            // Kunci frame rate sensor ke 30fps untuk mencegah overheating di chip Apple A7
            try rearCamera.lockForConfiguration()
            let targetFrameDuration = CMTime(value: 1, timescale: 30)
            let supports30fps = rearCamera.activeFormat.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= 30.0 && 30.0 <= range.maxFrameRate
            }
            if supports30fps {
                rearCamera.activeVideoMinFrameDuration = targetFrameDuration
                rearCamera.activeVideoMaxFrameDuration = targetFrameDuration
            }
            if rearCamera.isFocusModeSupported(.continuousAutoFocus) {
                rearCamera.focusMode = .continuousAutoFocus
            }
            if rearCamera.isExposureModeSupported(.continuousAutoExposure) {
                rearCamera.exposureMode = .continuousAutoExposure
            }
            rearCamera.unlockForConfiguration()
        } catch {
            captureSession.commitConfiguration()
            return
        }

        // 2. Real-Time Preview Output (AVCaptureVideoDataOutput)
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }

        if let connection = videoDataOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        // 3. Full-Res Still Photo Output (AVCapturePhotoOutput)
        photoOutput.isHighResolutionCaptureEnabled = true
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
        isSessionConfigured = true
        captureSession.startRunning()
    }

    private func startCameraSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isSessionConfigured, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    private func stopCameraSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            self.metalPreviewView?.flushMemory()
        }
    }

    private func registerLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleDidEnterBackground() {
        stopCameraSession()
    }

    @objc private func handleWillEnterForeground() {
        startCameraSessionIfNeeded()
    }

    // MARK: - Actions: Shutter (High-Res Capture) & Import .cube

    @objc private func handleShutterButtonTapped() {
        guard isSessionConfigured, !isCapturingPhoto else { return }
        isCapturingPhoto = true
        shutterButton.isEnabled = false

        // Animasi taktil tombol shutter + kilatan viewfinder
        UIView.animate(withDuration: 0.06, animations: {
            self.shutterButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            self.flashOverlayView.alpha = 0.85
        }, completion: { _ in
            UIView.animate(withDuration: 0.18) {
                self.shutterButton.transform = .identity
                self.flashOverlayView.alpha = 0.0
            }
        })

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let photoSettings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                photoSettings = AVCapturePhotoSettings()
            }
            photoSettings.isHighResolutionPhotoEnabled = true

            if let photoConnection = self.photoOutput.connection(with: .video),
               photoConnection.isVideoOrientationSupported {
                photoConnection.videoOrientation = .portrait
            }

            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    @objc private func handleImportCubeButtonTapped() {
        // UTI yang kompatibel dengan iOS 12.0+ untuk memilih file .cube dari Files / iCloud Drive
        let documentTypes = [
            "com.adobe.cube",
            "public.data",
            "public.item",
            String(kUTTypePlainText)
        ]
        let picker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        picker.delegate = self
        if #available(iOS 11.0, *) {
            picker.allowsMultipleSelection = false
        }
        present(picker, animated: true, completion: nil)
    }

    // MARK: - Retro Digicam UI Setup (Programmatic UIKit)

    private func setupRetroDigicamUI() {
        let safeGuide = view.safeAreaLayoutGuide

        // 1. Top Retro HUD Bar
        topBarView.translatesAutoresizingMaskIntoConstraints = false
        topBarView.backgroundColor = UIColor(white: 0.10, alpha: 1.0)
        view.addSubview(topBarView)

        modeBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeBadgeLabel.text = " [PHOTO 4:3] "
        modeBadgeLabel.font = UIFont(name: "Menlo-Bold", size: 11) ?? UIFont.boldSystemFont(ofSize: 11)
        modeBadgeLabel.textColor = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
        modeBadgeLabel.backgroundColor = UIColor(red: 0.96, green: 0.78, blue: 0.26, alpha: 1.0)
        modeBadgeLabel.layer.cornerRadius = 3
        modeBadgeLabel.clipsToBounds = true
        topBarView.addSubview(modeBadgeLabel)

        activePresetLabel.translatesAutoresizingMaskIntoConstraints = false
        activePresetLabel.text = "FILM: JAPANESE AIRY"
        activePresetLabel.font = UIFont(name: "Menlo-Bold", size: 11) ?? UIFont.boldSystemFont(ofSize: 11)
        activePresetLabel.textColor = UIColor(white: 0.92, alpha: 1.0)
        activePresetLabel.lineBreakMode = .byTruncatingTail
        topBarView.addSubview(activePresetLabel)

        importCubeButton.translatesAutoresizingMaskIntoConstraints = false
        importCubeButton.setTitle("+ Import .cube", for: .normal)
        importCubeButton.titleLabel?.font = UIFont(name: "Menlo-Bold", size: 11) ?? UIFont.boldSystemFont(ofSize: 11)
        importCubeButton.setTitleColor(UIColor(red: 0.96, green: 0.78, blue: 0.26, alpha: 1.0), for: .normal)
        importCubeButton.backgroundColor = UIColor(white: 0.18, alpha: 1.0)
        importCubeButton.layer.cornerRadius = 4
        importCubeButton.layer.borderWidth = 1
        importCubeButton.layer.borderColor = UIColor(red: 0.96, green: 0.78, blue: 0.26, alpha: 0.7).cgColor
        importCubeButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        importCubeButton.addTarget(self, action: #selector(handleImportCubeButtonTapped), for: .touchUpInside)
        topBarView.addSubview(importCubeButton)

        // 2. Viewfinder Container (4:3 Aspect Ratio)
        viewfinderContainer.translatesAutoresizingMaskIntoConstraints = false
        viewfinderContainer.backgroundColor = .black
        viewfinderContainer.layer.cornerRadius = 8
        viewfinderContainer.layer.borderWidth = 2
        viewfinderContainer.layer.borderColor = UIColor(white: 0.22, alpha: 1.0).cgColor
        viewfinderContainer.clipsToBounds = true
        view.addSubview(viewfinderContainer)

        metalPreviewView = MetalPreviewView(frame: .zero)
        metalPreviewView.translatesAutoresizingMaskIntoConstraints = false
        viewfinderContainer.addSubview(metalPreviewView)

        setupViewfinderGridOverlay()

        flashOverlayView.translatesAutoresizingMaskIntoConstraints = false
        flashOverlayView.backgroundColor = .white
        flashOverlayView.alpha = 0.0
        flashOverlayView.isUserInteractionEnabled = false
        viewfinderContainer.addSubview(flashOverlayView)

        statusToastLabel.translatesAutoresizingMaskIntoConstraints = false
        statusToastLabel.font = UIFont(name: "Menlo-Bold", size: 11) ?? UIFont.boldSystemFont(ofSize: 11)
        statusToastLabel.textColor = .black
        statusToastLabel.backgroundColor = UIColor(red: 0.96, green: 0.78, blue: 0.26, alpha: 0.95)
        statusToastLabel.textAlignment = .center
        statusToastLabel.layer.cornerRadius = 4
        statusToastLabel.clipsToBounds = true
        statusToastLabel.alpha = 0.0
        viewfinderContainer.addSubview(statusToastLabel)

        // 3. Bottom Controls Container (Horizontal Filter Carousel + Circular Shutter Button)
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1.0)
        view.addSubview(controlsContainer)

        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = CGSize(width: 76, height: 56)
        flowLayout.minimumInteritemSpacing = 8
        flowLayout.minimumLineSpacing = 8
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)

        presetCollectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        presetCollectionView.translatesAutoresizingMaskIntoConstraints = false
        presetCollectionView.backgroundColor = .clear
        presetCollectionView.showsHorizontalScrollIndicator = false
        presetCollectionView.dataSource = self
        presetCollectionView.delegate = self
        presetCollectionView.register(
            PresetCollectionViewCell.self,
            forCellWithReuseIdentifier: PresetCollectionViewCell.reuseIdentifier
        )
        controlsContainer.addSubview(presetCollectionView)

        // Prominent Circular Shutter Button
        let outerSize: CGFloat = 72
        let innerSize: CGFloat = 58

        shutterOuterRing.translatesAutoresizingMaskIntoConstraints = false
        shutterOuterRing.backgroundColor = .clear
        shutterOuterRing.layer.cornerRadius = outerSize * 0.5
        shutterOuterRing.layer.borderWidth = 3.5
        shutterOuterRing.layer.borderColor = UIColor(white: 0.90, alpha: 1.0).cgColor
        controlsContainer.addSubview(shutterOuterRing)

        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.backgroundColor = UIColor(red: 0.92, green: 0.90, blue: 0.86, alpha: 1.0)
        shutterButton.layer.cornerRadius = innerSize * 0.5
        shutterButton.layer.borderWidth = 1.5
        shutterButton.layer.borderColor = UIColor(white: 0.15, alpha: 1.0).cgColor
        shutterButton.addTarget(self, action: #selector(handleShutterButtonTapped), for: .touchUpInside)
        controlsContainer.addSubview(shutterButton)

        // Auto Layout Constraints (Mendukung layar 4" iPhone 5S 320x568 hingga layar modern)
        let aspectConstraint = viewfinderContainer.heightAnchor.constraint(
            equalTo: viewfinderContainer.widthAnchor,
            multiplier: 4.0 / 3.0
        )
        aspectConstraint.priority = UILayoutPriority(750)

        NSLayoutConstraint.activate([
            topBarView.topAnchor.constraint(equalTo: safeGuide.topAnchor),
            topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBarView.heightAnchor.constraint(equalToConstant: 42),

            modeBadgeLabel.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor, constant: 12),
            modeBadgeLabel.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            modeBadgeLabel.heightAnchor.constraint(equalToConstant: 20),

            importCubeButton.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor, constant: -12),
            importCubeButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),

            activePresetLabel.leadingAnchor.constraint(equalTo: modeBadgeLabel.trailingAnchor, constant: 8),
            activePresetLabel.trailingAnchor.constraint(lessThanOrEqualTo: importCubeButton.leadingAnchor, constant: -8),
            activePresetLabel.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),

            viewfinderContainer.topAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: 6),
            viewfinderContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            viewfinderContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            aspectConstraint,

            metalPreviewView.topAnchor.constraint(equalTo: viewfinderContainer.topAnchor),
            metalPreviewView.leadingAnchor.constraint(equalTo: viewfinderContainer.leadingAnchor),
            metalPreviewView.trailingAnchor.constraint(equalTo: viewfinderContainer.trailingAnchor),
            metalPreviewView.bottomAnchor.constraint(equalTo: viewfinderContainer.bottomAnchor),

            flashOverlayView.topAnchor.constraint(equalTo: viewfinderContainer.topAnchor),
            flashOverlayView.leadingAnchor.constraint(equalTo: viewfinderContainer.leadingAnchor),
            flashOverlayView.trailingAnchor.constraint(equalTo: viewfinderContainer.trailingAnchor),
            flashOverlayView.bottomAnchor.constraint(equalTo: viewfinderContainer.bottomAnchor),

            statusToastLabel.bottomAnchor.constraint(equalTo: viewfinderContainer.bottomAnchor, constant: -12),
            statusToastLabel.centerXAnchor.constraint(equalTo: viewfinderContainer.centerXAnchor),
            statusToastLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            statusToastLabel.heightAnchor.constraint(equalToConstant: 26),

            controlsContainer.topAnchor.constraint(equalTo: viewfinderContainer.bottomAnchor, constant: 6),
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: safeGuide.bottomAnchor),
            controlsContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 152),

            presetCollectionView.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 6),
            presetCollectionView.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            presetCollectionView.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            presetCollectionView.heightAnchor.constraint(equalToConstant: 60),

            shutterOuterRing.topAnchor.constraint(equalTo: presetCollectionView.bottomAnchor, constant: 10),
            shutterOuterRing.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
            shutterOuterRing.widthAnchor.constraint(equalToConstant: outerSize),
            shutterOuterRing.heightAnchor.constraint(equalToConstant: outerSize),
            shutterOuterRing.bottomAnchor.constraint(lessThanOrEqualTo: controlsContainer.bottomAnchor, constant: -10),

            shutterButton.centerXAnchor.constraint(equalTo: shutterOuterRing.centerXAnchor),
            shutterButton.centerYAnchor.constraint(equalTo: shutterOuterRing.centerYAnchor),
            shutterButton.widthAnchor.constraint(equalToConstant: innerSize),
            shutterButton.heightAnchor.constraint(equalToConstant: innerSize)
        ])
    }

    private func setupViewfinderGridOverlay() {
        gridOverlayView.translatesAutoresizingMaskIntoConstraints = false
        gridOverlayView.isUserInteractionEnabled = false
        gridOverlayView.backgroundColor = .clear
        viewfinderContainer.addSubview(gridOverlayView)

        NSLayoutConstraint.activate([
            gridOverlayView.topAnchor.constraint(equalTo: viewfinderContainer.topAnchor),
            gridOverlayView.leadingAnchor.constraint(equalTo: viewfinderContainer.leadingAnchor),
            gridOverlayView.trailingAnchor.constraint(equalTo: viewfinderContainer.trailingAnchor),
            gridOverlayView.bottomAnchor.constraint(equalTo: viewfinderContainer.bottomAnchor)
        ])
    }

    private func showToast(_ text: String) {
        DispatchQueue.main.async {
            self.statusToastLabel.text = "  \(text)  "
            UIView.animate(withDuration: 0.18, animations: {
                self.statusToastLabel.alpha = 1.0
            }, completion: { _ in
                UIView.animate(withDuration: 0.25, delay: 1.6, options: [], animations: {
                    self.statusToastLabel.alpha = 0.0
                }, completion: nil)
            })
        }
    }

    private func showPermissionAlert(message: String) {
        let alert = UIAlertController(title: "Izin Diperlukan", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tutup", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Buka Pengaturan", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        })
        present(alert, animated: true, completion: nil)
    }

    private func showErrorAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Real-Time 30fps Live Preview)

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Jangan memproses frame preview baru saat sedang merender foto resolusi tinggi
        // untuk menjaga puncak RAM di bawah batas 1 GB iPhone 5S
        guard !isCapturingPhoto else { return }

        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)

            let filteredImage: CIImage
            filterLock.lock()
            if let filter = activePreviewFilter {
                filter.setValue(sourceImage, forKey: kCIInputImageKey)
                filteredImage = filter.outputImage ?? sourceImage
                // Putuskan referensi inputImage setelah outputImage diambil agar pixelBuffer tidak tertahan
                filter.setValue(nil, forKey: kCIInputImageKey)
            } else {
                filteredImage = sourceImage
            }
            filterLock.unlock()

            metalPreviewView.render(image: filteredImage)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate (High-Res WYSIWYG Photo Capture)

extension CameraViewController: AVCapturePhotoCaptureDelegate {

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        defer {
            DispatchQueue.main.async {
                self.isCapturingPhoto = false
                self.shutterButton.isEnabled = true
            }
        }

        if let error = error {
            showErrorAlert(title: "Gagal Memotret", message: error.localizedDescription)
            return
        }

        // Ambil snapshot preset yang sedang aktif
        let presets = PresetManager.shared.presets
        let activePreset = presets.indices.contains(selectedPresetIndex) ? presets[selectedPresetIndex] : nil
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        // Proses foto resolusi penuh di dalam autoreleasepool ketat agar RAM langsung dibebaskan
        var finalJPEGData: Data?
        autoreleasepool {
            guard let rawPhotoData = photo.fileDataRepresentation(),
                  var fullResCIImage = CIImage(data: rawPhotoData) else {
                return
            }

            // Koreksi orientasi EXIF agar foto tersimpan tegak sesuai viewfinder
            if let orientationValue = photo.metadata[kCGImagePropertyOrientation as String] as? UInt32,
               let exifOrientation = CGImagePropertyOrientation(rawValue: orientationValue) {
                fullResCIImage = fullResCIImage.oriented(forExifOrientation: Int32(exifOrientation.rawValue))
            } else if let orientationNum = photo.metadata[kCGImagePropertyOrientation as String] as? Int {
                fullResCIImage = fullResCIImage.oriented(forExifOrientation: Int32(orientationNum))
            }

            // Terapkan filter CIColorCube aktif (buat instance baru agar thread-safe)
            let outputCIImage: CIImage
            if let filter = activePreset?.makeFilter() {
                filter.setValue(fullResCIImage, forKey: kCIInputImageKey)
                outputCIImage = filter.outputImage ?? fullResCIImage
            } else {
                outputCIImage = fullResCIImage
            }

            // Gunakan shared Metal CIContext untuk mengenkode langsung ke JPEG tanpa UIImage perantara
            if let context = metalPreviewView.ciContext {
                let options: [CIImageRepresentationOption: Any] = [
                    CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92
                ]
                finalJPEGData = context.jpegRepresentation(
                    of: outputCIImage,
                    colorSpace: colorSpace,
                    options: options
                )
                context.clearCaches()
            }
        }

        guard let jpegDataToSave = finalJPEGData else {
            showErrorAlert(title: "Gagal Memproses Foto", message: "Tidak dapat merender filter LUT pada foto.")
            return
        }

        saveJPEGToPhotoLibrary(jpegDataToSave, presetName: activePreset?.shortCode ?? "RETRO")
    }

    private func saveJPEGToPhotoLibrary(_ jpegData: Data, presetName: String) {
        let saveBlock: () -> Void = { [weak self] in
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: jpegData, options: nil)
            }, completionHandler: { [weak self] success, error in
                if success {
                    self?.showToast("SAVED [\(presetName)]")
                } else {
                    self?.showErrorAlert(
                        title: "Gagal Menyimpan",
                        message: error?.localizedDescription ?? "Tidak dapat menyimpan foto ke Camera Roll."
                    )
                }
            })
        }

        let status = PHPhotoLibrary.authorizationStatus()
        if status == .authorized {
            saveBlock()
        } else if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                if newStatus == .authorized {
                    saveBlock()
                } else {
                    DispatchQueue.main.async {
                        self?.showPermissionAlert(message: "Izinkan akses Foto untuk menyimpan hasil jepretan ke Camera Roll.")
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.showPermissionAlert(message: "Izinkan akses Foto di Pengaturan iOS untuk menyimpan hasil jepretan.")
            }
        }
    }
}

// MARK: - UICollectionViewDataSource & UICollectionViewDelegate (Filter Carousel)

extension CameraViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return PresetManager.shared.presets.count
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PresetCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as? PresetCollectionViewCell else {
            return UICollectionViewCell()
        }

        let preset = PresetManager.shared.presets[indexPath.item]
        cell.configure(with: preset, isSelected: indexPath.item == selectedPresetIndex)
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item != selectedPresetIndex else { return }

        let feedback = UISelectionFeedbackGenerator()
        feedback.selectionChanged()

        selectPreset(at: indexPath.item)
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
    }
}

// MARK: - UIDocumentPickerDelegate (Custom .cube Import)

extension CameraViewController: UIDocumentPickerDelegate {

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedURL = urls.first else { return }
        handleImportedCubeURL(selectedURL)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        handleImportedCubeURL(url)
    }

    private func handleImportedCubeURL(_ url: URL) {
        guard url.pathExtension.lowercased() == "cube" else {
            showErrorAlert(
                title: "Format File Tidak Didukung",
                message: "Pilih file 3D LUT dengan ekstensi .cube."
            )
            return
        }

        do {
            let importedPreset = try PresetManager.shared.importCustomCubeFile(from: url)
            if let index = PresetManager.shared.presets.firstIndex(where: { $0.id == importedPreset.id }) {
                selectPreset(at: index)
                let indexPath = IndexPath(item: index, section: 0)
                presetCollectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
            }
            showToast("LUT IMPORTED: \(importedPreset.shortCode)")
        } catch {
            showErrorAlert(title: "Gagal Mengimpor .cube", message: error.localizedDescription)
        }
    }
}
