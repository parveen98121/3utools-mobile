import SwiftUI
import VisionKit
import UIKit

struct QRScannerView: View {
    @State private var permission = PermissionService.camera()
    @State private var scanned: [String] = []
    @State private var copied: String?

    private var scannerSupported: Bool {
        DataScannerViewController.isSupported
    }

    var body: some View {
        Group {
            if !scannerSupported {
                EmptyStateView(title: "Scanner not supported",
                               systemImage: "qrcode.viewfinder",
                               message: "Live scanning needs an iPhone with an A12 chip or newer. It is also unavailable in the simulator.")
            } else if !permission.isUsable {
                PermissionPromptView(
                    title: "Camera",
                    message: "The camera is used only to read QR codes and barcodes on this screen. Nothing is recorded.",
                    systemImage: "camera.fill",
                    state: permission
                ) {
                    Task { permission = await PermissionService.requestCamera() }
                }
            } else {
                scanner
            }
        }
        .navigationTitle("QR scanner")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { permission = PermissionService.camera() }
    }

    private var scanner: some View {
        VStack(spacing: 0) {
            DataScannerRepresentable { value in
                if scanned.first != value {
                    scanned.insert(value, at: 0)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) {
                Text("Point the camera at a QR code or barcode")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 12)
            }

            if !scanned.isEmpty {
                List {
                    Section("Scanned") {
                        ForEach(Array(scanned.enumerated()), id: \.offset) { _, value in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(value)
                                    .font(.footnote)
                                    .textSelection(.enabled)
                                    .lineLimit(4)
                                HStack(spacing: 10) {
                                    Button(copied == value ? "Copied" : "Copy") {
                                        UIPasteboard.general.string = value
                                        copied = value
                                    }
                                    ShareLink(item: value) { Text("Share") }
                                    if let url = webURL(from: value) {
                                        Button("Open link") { UIApplication.shared.open(url) }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    /// Only http and https links get an Open button; other content is shown as text.
    private func webURL(from value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if !controller.isScanning, DataScannerViewController.isAvailable {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report([item])
        }

        private func report(_ items: [RecognizedItem]) {
            for item in items {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    onScan(value)
                }
            }
        }
    }
}
