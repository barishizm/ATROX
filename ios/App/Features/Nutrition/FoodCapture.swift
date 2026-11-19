import AVFoundation
import DesignSystem
import SwiftUI
import UIKit
import VisionKit

/// The in-app camera for one meal photo: a live preview inside ATROX with its own shutter, never the system camera sheet.
/// Hidden where there is no camera (Simulator).
struct CameraPicker: View {
    let onImage: (UIImage?) -> Void
    @State private var model = CameraModel()
    @Environment(\.openURL) private var openURL

    static var isAvailable: Bool { AVCaptureDevice.default(for: .video) != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.state {
            case .starting:
                ProgressView().tint(.white)
            case .running:
                CameraPreview(session: model.box.session).ignoresSafeArea()
            case .denied, .failed:
                unavailable
            }
            VStack {
                HStack {
                    roundButton("xmark", label: "nutrition.camera.close") { onImage(nil) }
                    Spacer()
                    if model.state == .running {
                        roundButton(model.flashOn ? "bolt.fill" : "bolt.slash.fill", label: "nutrition.camera.flash") { model.flashOn.toggle() }
                    }
                }
                .padding(Spacing.md)
                Spacer()
                if model.state == .running { shutter }
            }
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
        .accessibilityIdentifier("food-camera")
    }

    private var shutter: some View {
        Button {
            Task { if let image = await model.capture() { onImage(image) } }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(.white).frame(width: 62, height: 62).opacity(model.isCapturing ? 0.5 : 1)
            }
        }
        .disabled(model.isCapturing)
        .accessibilityLabel(Text("nutrition.camera.shutter"))
        .accessibilityIdentifier("food-camera-shutter")
        .padding(.bottom, Spacing.xl)
    }

    private var unavailable: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.7)).accessibilityHidden(true)
            Text(model.state == .denied ? "nutrition.camera.denied.title" : "nutrition.camera.failed.title")
                .font(DSFont.headline).foregroundStyle(.white)
            Text(model.state == .denied ? "nutrition.camera.denied.message" : "nutrition.camera.failed.message")
                .font(DSFont.footnote).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            if model.state == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("nutrition.camera.settings") { openURL(url) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.lg)
    }

    private func roundButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.title3.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(Text(label))
    }
}

@MainActor @Observable
final class CameraModel {
    enum State { case starting, running, denied, failed }

    private(set) var state: State = .starting
    private(set) var isCapturing = false
    var flashOn = false
    let box = CameraBox()

    func start() async {
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else { state = .denied; return }
        state = await box.start() ? .running : .failed
    }

    func stop() { box.stop() }

    func capture() async -> UIImage? {
        isCapturing = true
        defer { isCapturing = false }
        guard let data = await box.capture(flash: flashOn) else { return nil }
        return UIImage(data: data)
    }
}

/// Owns the capture session; all session work stays on one serial queue.
final class CameraBox: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "atrox.food-camera")
    private var configured = false
    private var pending: CheckedContinuation<Data?, Never>?

    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                if !self.configured {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                       let input = try? AVCaptureDeviceInput(device: device),
                       self.session.canAddInput(input), self.session.canAddOutput(self.output) {
                        self.session.addInput(input)
                        self.session.addOutput(self.output)
                        self.configured = true
                    }
                    self.session.commitConfiguration()
                }
                if self.configured, !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: self.configured)
            }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func capture(flash: Bool) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.pending == nil else { continuation.resume(returning: nil); return }
                self.pending = continuation
                let settings = AVCapturePhotoSettings()
                if self.output.supportedFlashModes.contains(.on) { settings.flashMode = flash ? .on : .off }
                // The app is portrait-only on iPhone, so the photo is always captured upright.
                self.output.connection(with: .video)?.videoRotationAngle = 90
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async {
            self.pending?.resume(returning: data)
            self.pending = nil
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }  // swiftlint:disable:this force_cast
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

/// Live barcode scanning with VisionKit; `isSupported` is false in the Simulator and on devices without it.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isSupported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var delivered = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for case .barcode(let barcode) in addedItems {
                if let code = barcode.payloadStringValue {
                    delivered = true
                    onCode(code)
                    return
                }
            }
        }
    }
}
