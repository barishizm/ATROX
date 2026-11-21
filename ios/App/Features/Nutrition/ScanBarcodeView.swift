import AVFoundation
import DataKit
import DesignSystem
import SwiftUI

/// Full-screen barcode scan: a framed live scanner, a flashlight, and a typed-number fallback (the Simulator has no scanner).
struct ScanBarcodeView: View {
    let service: any PackagedFoodService
    let onFound: (PackagedFood) -> Void
    let onClose: () -> Void

    @State private var scanned = false
    @State private var isLoading = false
    @State private var message: LocalizedStringKey?
    @State private var manualCode = ""
    @State private var torchOn = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: Spacing.md)
            scannerFrame
            Text("nutrition.scan.hint").font(DSFont.callout).foregroundStyle(DSColor.textSecondary).padding(.top, Spacing.md)
            if isLoading { ProgressView().padding(.top, Spacing.sm) }
            if let message { Text(message).font(DSFont.footnote).foregroundStyle(DSColor.warning).padding(.top, Spacing.xs) }
            Spacer(minLength: Spacing.md)
            manualEntry
        }
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background.ignoresSafeArea())
        .onDisappear { Self.setTorch(false) }
        .accessibilityIdentifier("scan-barcode")
    }

    private var topBar: some View {
        HStack {
            if BarcodeScannerView.isSupported {
                roundButton(torchOn ? "flashlight.on.fill" : "flashlight.off.fill", label: "nutrition.scan.torch") {
                    torchOn.toggle()
                    Self.setTorch(torchOn)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Text("nutrition.scan.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            Spacer()
            roundButton("xmark", label: "nutrition.camera.close", action: onClose).accessibilityIdentifier("scan-close")
        }
        .padding(.top, Spacing.sm)
    }

    private var scannerFrame: some View {
        ZStack {
            if BarcodeScannerView.isSupported {
                BarcodeScannerView { code in
                    guard !scanned else { return }
                    scanned = true
                    Task { await lookup(code) }
                }
            } else {
                DSColor.surface
                Image(systemName: "barcode.viewfinder").font(.system(size: 64)).foregroundStyle(DSColor.textTertiary).accessibilityHidden(true)
            }
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(.white, lineWidth: 3).padding(8)
        }
        .frame(maxWidth: 340).aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .accessibilityLabel(Text("nutrition.barcode.scanner.a11y"))
    }

    private var manualEntry: some View {
        HStack {
            TextField("nutrition.barcode.number", text: $manualCode).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("barcode-number")
            Button("nutrition.barcode.find") { Task { await lookup(manualCode) } }
                .buttonStyle(.borderedProminent).tint(DSColor.accentFill)
                .disabled(!OpenFoodFacts.isValidBarcode(manualCode) || isLoading)
                .accessibilityIdentifier("barcode-find")
        }
        .padding(.bottom, Spacing.md)
    }

    private func roundButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.title3.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                .frame(width: 44, height: 44).glassEffect(Glass.regular.interactive(), in: Circle())
        }
        .accessibilityLabel(Text(label))
    }

    private func lookup(_ code: String) async {
        let digits = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OpenFoodFacts.isValidBarcode(digits) else {
            message = "nutrition.barcode.invalid"
            scanned = false
            return
        }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            if let food = try await service.product(barcode: digits) {
                Self.setTorch(false)
                onFound(food)
            } else {
                message = "nutrition.barcode.notfound"
                scanned = false
            }
        } catch {
            message = "nutrition.barcode.error"
            scanned = false
        }
    }

    private static func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch, device.isTorchModeSupported(on ? .on : .off) else { return }
        // Setting the mode without the lock raises; the scanner may hold the device.
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}
