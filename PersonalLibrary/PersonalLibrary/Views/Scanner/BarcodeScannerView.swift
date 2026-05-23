import SwiftUI
import AVFoundation

/// 条形码扫描视图 — 使用摄像头扫描 ISBN 条形码
struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedISBN: String?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, ScannerViewControllerDelegate {
        let parent: BarcodeScannerView

        init(_ parent: BarcodeScannerView) {
            self.parent = parent
        }

        func didFindBarcode(_ code: String) {
            parent.scannedISBN = code
            parent.isPresented = false
        }

        func didFailWithError(_ error: Error) {
            parent.isPresented = false
        }
    }
}

// MARK: - Scanner View Controller

protocol ScannerViewControllerDelegate: AnyObject {
    func didFindBarcode(_ code: String)
    func didFailWithError(_ error: Error)
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            showNoCameraUI()
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            delegate?.didFailWithError(ScannerError.invalidDeviceInput)
            captureSession = nil
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            delegate?.didFailWithError(ScannerError.invalidDeviceInput)
            captureSession = nil
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            // 支持 EAN-13（国际标准书号条形码）和 EAN-8
            metadataOutput.metadataObjectTypes = [.ean13, .ean8]
        } else {
            delegate?.didFailWithError(ScannerError.invalidDeviceInput)
            captureSession = nil
            return
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer

        // 添加扫描框指引
        addScanOverlay()

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func addScanOverlay() {
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)

        // 中间扫描区域
        let scanRect = CGRect(
            x: view.bounds.width * 0.1,
            y: view.bounds.height * 0.3,
            width: view.bounds.width * 0.8,
            height: view.bounds.height * 0.15
        )

        let borderView = UIView(frame: scanRect)
        borderView.layer.borderColor = UIColor.systemBlue.cgColor
        borderView.layer.borderWidth = 2
        borderView.layer.cornerRadius = 8
        borderView.backgroundColor = .clear
        overlayView.addSubview(borderView)

        // 提示文字
        let label = UILabel()
        label.text = "将条形码对准框内"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.frame = CGRect(
            x: 0,
            y: scanRect.maxY + 20,
            width: view.bounds.width,
            height: 30
        )
        overlayView.addSubview(label)
    }

    private func showNoCameraUI() {
        let label = UILabel()
        label.text = "模拟器不支持摄像头\n请在真机上测试扫码功能"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.frame = view.bounds
        view.addSubview(label)
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else { return }

        // 震动反馈
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

        captureSession?.stopRunning()
        delegate?.didFindBarcode(stringValue)
    }
}

enum ScannerError: Error, LocalizedError {
    case invalidDeviceInput
    case cameraNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidDeviceInput: return "无法访问摄像头"
        case .cameraNotAvailable: return "设备没有摄像头"
        }
    }
}
