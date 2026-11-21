import SwiftUI
import AppKit
import LeonardoCore
import LeonardoSync

/// A signing rubric is proof input, not a document graphic or a shared
/// library entry. Profile persistence and session persistence are handled by
/// their separate consented stores after the signer confirms the assignment
/// or exact location.
struct GuidedSigningRubricCapture: View {
    let title: String
    let complete: (LeonardoRubric) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rubric: LeonardoRubric
    @State private var color = Color.black
    @State private var width = 3.0
    @State private var style = LeonardoInkStyle.solid
    @State private var linkedDevice = false

    init(title: String, initialRubric: LeonardoRubric?, complete: @escaping (LeonardoRubric) -> Void) {
        self.title = title
        self.complete = complete
        _rubric = State(initialValue: initialRubric ?? LeonardoRubric())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: "signature").font(.title2.bold())
            Text(L10n.text("This rubric is used only for guided signing and is not added to the shared rubric library."))
                .font(.caption).foregroundStyle(.secondary)
            if linkedDevice {
                GuidedSigningLinkedRubric(controller: .shared) { received in
                    complete(received)
                    dismiss()
                }
            } else {
                localCanvas
            }
            HStack {
                Button(linkedDevice ? L10n.text("Draw your rubric") : L10n.text("Use a linked Little Leonardo")) {
                    linkedDevice.toggle()
                }
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                if !linkedDevice {
                    Button(L10n.text("Use rubric")) {
                        complete(rubric)
                        dismiss()
                    }
                    .buttonStyle(PremiumButtonStyle(prominent: true))
                    .disabled(!rubric.isValid)
                }
            }
            .buttonStyle(PremiumButtonStyle())
        }
        .padding(24)
        .frame(width: 648)
    }

    private var localCanvas: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Color")).font(.caption)
                    ColorPicker(L10n.text("Color"), selection: $color, supportsOpacity: false).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Stroke width")).font(.caption)
                    HStack {
                        Slider(value: $width, in: 0.5...24).frame(width: 160)
                            .accessibilityLabel(L10n.text("Stroke width"))
                        Text(width, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit().frame(width: 42)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Stroke style")).font(.caption)
                    Picker(L10n.text("Stroke style"), selection: $style) {
                        Text(L10n.text("Solid")).tag(LeonardoInkStyle.solid)
                        Text(L10n.text("Brush")).tag(LeonardoInkStyle.brush)
                    }.labelsHidden().frame(width: 160)
                }
                Spacer(minLength: 0)
            }
            RubricCanvas(rubric: $rubric, color: RubricDrawing.hex(NSColor(color)), width: width, style: style)
                .frame(width: 600, height: 200).background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.3)))
                .accessibilityLabel(L10n.text("Draw your rubric"))
            HStack {
                Button(L10n.text("Undo")) {
                    if !rubric.strokes.isEmpty { rubric.strokes.removeLast() }
                }.disabled(rubric.strokes.isEmpty)
                Button(L10n.text("Clear")) { rubric = LeonardoRubric() }
                    .disabled(rubric.strokes.isEmpty)
            }
            .buttonStyle(PremiumButtonStyle(compact: true))
        }
    }
}

/// Uses the existing device capture protocol with no document context. The
/// received ink remains a draft until the Mac signer confirms its location.
private struct GuidedSigningLinkedRubric: View {
    let controller: DesktopSyncController
    let use: (LeonardoRubric) -> Void
    @State private var capture: RubricCaptureRecord?
    @State private var job: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let capture {
                if !capture.isCancellationRequested, let response = capture.response {
                    Label(L10n.text("Review received rubric"), systemImage: "signature")
                        .font(.headline)
                    Image(nsImage: RubricDrawing.inspectorPreview(response.rubric))
                        .resizable().aspectRatio(contentMode: .fit).frame(height: 96)
                        .accessibilityLabel(L10n.text("Received rubric preview"))
                    Button(L10n.text("Use rubric")) { use(response.rubric) }
                        .buttonStyle(PremiumButtonStyle(prominent: true))
                        .disabled(!response.rubric.isValid)
                } else if !capture.isTerminal && !capture.isCancellationResolvedByCompletion {
                    Label(L10n.format("Waiting for %@ to draw the rubric…", capture.targetDeviceName), systemImage: "iphone")
                    Button(L10n.text("Cancel request")) { cancel(capture.id) }
                } else {
                    Button(L10n.text("Request another rubric")) {
                        self.capture = nil
                        error = nil
                    }
                }
            } else {
                Menu {
                    ForEach(controller.supportedRubricDevices) { device in
                        Button(device.name) { request(device) }
                    }
                } label: {
                    Label(L10n.text("Request from linked device"), systemImage: "paperplane")
                }
                .disabled(controller.rubricCaptureAvailability != .ready)
                Text(L10n.text(controller.rubricCaptureAvailability.messageKey))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Refresh linked devices")) {
                    Task { await controller.refreshConsent() }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .task { await controller.refreshConsent() }
        .onDisappear {
            if let capture, !capture.isTerminal, capture.response == nil, !capture.isCancellationRequested {
                Task { _ = try? await controller.cancelRubricCapture(requestID: capture.id) }
            }
            job?.cancel()
        }
    }

    private func request(_ device: PairedDevice) {
        do {
            let record = try controller.prepareRubricCapture(
                targetDeviceID: device.id, targetDeviceName: device.name,
                documentURL: nil, source: "", fieldID: nil
            )
            capture = record
            error = nil
            job = Task {
                do {
                    let created = try await controller.beginRubricCapture(
                        requestID: record.id, targetDeviceID: device.id, targetDeviceName: device.name,
                        documentURL: nil, source: "", fieldID: nil
                    )
                    try Task.checkCancellation()
                    capture = created
                    guard created.response == nil, !created.isTerminal else { return }
                    try await RubricCapturePolling.run(requestID: created.id, refresh: {
                        try await controller.refreshRubricCapture(requestID: $0)
                    }, receive: { capture = $0 })
                } catch is CancellationError {
                } catch {
                    if !Task.isCancelled { self.error = L10n.text(error.localizedDescription) }
                }
            }
        } catch {
            self.error = L10n.text(error.localizedDescription)
        }
    }

    private func cancel(_ id: UUID) {
        job?.cancel()
        job = Task {
            do {
                capture = try await controller.cancelRubricCapture(requestID: id)
            } catch {
                capture = controller.rubricCapture(id: id)
                self.error = L10n.text(error.localizedDescription)
            }
        }
    }
}
