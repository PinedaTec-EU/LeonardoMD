import SwiftUI
import AVFoundation
import VisionKit
import LeonardoSyncTransport

enum MobileQRScannerFailureReason {
    case cameraStart
    case cameraUnavailable
    case invalidInvitation

    func message(spanish: Bool) -> String {
        switch self {
        case .cameraStart:
            spanish ? "No se pudo iniciar la cámara. Puedes pegar el enlace del QR."
                : "The camera could not start. You can paste the QR link."
        case .cameraUnavailable:
            spanish ? "La cámara dejó de estar disponible. Puedes cancelar y volver a intentarlo."
                : "The camera is no longer available. Cancel and try again."
        case .invalidInvitation:
            spanish ? "El QR no es válido o ha caducado. Genera uno nuevo en LeonardoMD."
                : "This QR code is invalid or expired. Generate a new one in LeonardoMD."
        }
    }
}

@MainActor
enum MobileQRScannerDiagnostics {
    static func notice(
        for error: Error,
        reason: MobileQRScannerFailureReason,
        diagnosticLog: MobileDiagnosticLog? = nil,
        spanish: Bool
    ) -> MobileErrorNotice {
        MobileErrorNotice.record(
            error,
            operation: .scanner,
            message: reason.message(spanish: spanish),
            diagnosticLog: diagnosticLog,
            spanish: spanish)
    }
}

struct MobileQRScannerScreen: View {
    let spanish: Bool
    let receive: (String) -> Void
    let failure: (MobileErrorNotice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ready = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if ready, message == nil {
                    MobileQRScanner(receive: { payload in
                        receive(payload)
                        dismiss()
                    }, failure: { error, reason in
                        failure(MobileQRScannerDiagnostics.notice(
                            for: error, reason: reason, spanish: spanish))
                        dismiss()
                    })
                } else if let message {
                    ContentUnavailableView("Cámara no disponible", systemImage: "camera",
                        description: Text(message))
                        .accessibilityIdentifier("scanner-unavailable")
                } else { ProgressView("Preparando cámara…") }
            }
            .classicSurface()
            .navigationTitle("Escanear QR de LeonardoMD")
            .toolbar { Button("Cancelar") { dismiss() } }
            .task {
                guard DataScannerViewController.isSupported else {
                    message = "Este dispositivo no admite el lector. Puedes pegar el enlace del QR."
                    return
                }
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                guard allowed, DataScannerViewController.isAvailable else {
                    message = "Permite el acceso a la cámara en Ajustes o pega el enlace del QR."
                    return
                }
                ready = true
            }
        }
    }
}

private struct MobileQRScanner: UIViewControllerRepresentable {
    let receive: (String) -> Void
    let failure: (Error, MobileQRScannerFailureReason) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(receive: receive, failure: failure) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() }
        catch {
            Task { @MainActor in context.coordinator.fail(error, reason: .cameraStart) }
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        coordinator.finished = true
        scanner.stopScanning()
        scanner.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let receive: (String) -> Void
        let failure: (Error, MobileQRScannerFailureReason) -> Void
        var finished = false
        init(receive: @escaping (String) -> Void, failure: @escaping (Error, MobileQRScannerFailureReason) -> Void) {
            self.receive = receive; self.failure = failure
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems { accept(item, scanner: dataScanner) }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            accept(item, scanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            dataScanner.stopScanning()
            fail(error, reason: .cameraUnavailable)
        }

        private func accept(_ item: RecognizedItem, scanner: DataScannerViewController) {
            guard !finished, case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                  payload.utf8.count <= 4 * 1_024, let url = URL(string: payload),
                  url.scheme == "littleleonardo" else { return }
            do { _ = try DirectPairingQR.decode(url, now: Date()) }
            catch {
                scanner.stopScanning()
                fail(error, reason: .invalidInvitation)
                return
            }
            finished = true
            scanner.stopScanning()
            receive(payload)
        }

        func fail(_ error: Error, reason: MobileQRScannerFailureReason) {
            guard !finished else { return }
            finished = true
            failure(error, reason)
        }
    }
}
