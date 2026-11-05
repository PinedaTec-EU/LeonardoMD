import SwiftUI
import AppKit
import LeonardoCore
import LeonardoSync

struct RubricEditor: View {
    let request: RubricRequest
    let clearField: (() -> Bool)?
    let complete: (String, LeonardoRubric, Bool) -> Bool
    let syncController: DesktopSyncController?
    let saveRemote: ((RubricCaptureRecord, String) -> String?)?
    let completeRemote: ((RubricCaptureRecord, String) -> Bool)?
    @Environment(\.dismiss) private var dismiss
    @State private var rubric = LeonardoRubric()
    @State private var label = ""
    @State private var color = Color.black
    @State private var width = 3.0
    @State private var style = LeonardoInkStyle.solid
    @State private var saveToLibrary = true
    @State private var library: RubricLibrary
    @State private var error: String?
    @State private var remoteCapture: RubricCaptureRecord?
    @State private var remoteLabel = ""
    @State private var remoteError: String?
    @State private var remoteTask: Task<Void, Never>?
    @State private var remoteCreating = false

    init(request: RubricRequest, library: RubricLibrary, clearField: (() -> Bool)? = nil,
         syncController: DesktopSyncController? = nil,
         saveRemote: ((RubricCaptureRecord, String) -> String?)? = nil,
         completeRemote: ((RubricCaptureRecord, String) -> Bool)? = nil,
         complete: @escaping (String, LeonardoRubric, Bool) -> Bool) {
        self.request = request; self.complete = complete; self.clearField = clearField
        self.syncController = syncController; self.saveRemote = saveRemote; self.completeRemote = completeRemote
        _library = State(initialValue: library)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Rubrics")).font(.title2.bold())
            if let loadError = library.loadError { Text(loadError).foregroundStyle(.red) }
            if !library.entries.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(library.entries) { entry in
                            VStack {
                                Button {
                                    if complete(entry.label, entry.rubric, false) { dismiss() }
                                } label: {
                                    VStack { Image(nsImage: RubricDrawing.thumbnail(entry.rubric)); Text(entry.label).lineLimit(1) }
                                }.help(L10n.text("Insert rubric"))
                                Button(L10n.text("Delete"), role: .destructive) {
                                    do { try library.remove(id: entry.id) } catch { self.error = error.localizedDescription }
                                }.font(.caption)
                            }
                        }
                    }
                }.frame(height: 85)
            }
            if let syncController { remoteCaptureSection(syncController) }
            TextField(L10n.text("Rubric label"), text: $label).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("rubric-label")
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
                        Text(width, format: .number.precision(.fractionLength(1))).monospacedDigit().frame(width: 42)
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
            RubricCanvas(rubric: $rubric, color: inkColor, width: width, style: style)
                .frame(width: 600, height: 200).background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.3)))
                .accessibilityLabel(L10n.text("Draw your rubric"))
            HStack {
                Button(L10n.text("Undo")) { if !rubric.strokes.isEmpty { rubric.strokes.removeLast() } }.disabled(rubric.strokes.isEmpty)
                Button(L10n.text("Clear")) { rubric = LeonardoRubric() }.disabled(rubric.strokes.isEmpty)
                Spacer()
                if request.savesToLibrary { Text(L10n.text("New rubrics are saved in your library.")).font(.caption) }
                else { Toggle(L10n.text("Save in my rubrics"), isOn: $saveToLibrary) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if let clearField {
                    Button(L10n.text("Remove rubric")) { if clearField() { dismiss() } }
                }
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("Insert rubric")) {
                    if complete(label, rubric, request.savesToLibrary || saveToLibrary) { dismiss() }
                    else { error = L10n.text("The rubric could not be inserted. Check the document and try again.") }
                }.disabled(!rubric.isValid || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || label.count > 120)
            }
        }.padding(24).frame(width: 648)
            .onAppear {
                library.refresh()
                Task { await syncController?.refreshConsent() }
                guard let syncController,
                      let existing = syncController.rubricCapture(for: request.documentURL, source: request.source) else { return }
                remoteCapture = existing
                if let response = existing.response { remoteLabel = response.label }
                else { remoteLabel = existing.labelHint ?? label }
                if existing.request?.state == .pending || existing.request?.state == .accepted {
                    pollRemote(syncController, requestID: existing.id)
                }
            }
            .onDisappear { remoteTask?.cancel() }
    }

    @ViewBuilder
    private func remoteCaptureSection(_ controller: DesktopSyncController) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text("Use a linked Little Leonardo"), systemImage: "iphone.and.arrow.forward")
                .font(.headline)
            Text(L10n.text("The linked device draws the rubric. Review it here before saving or inserting it."))
                .font(.caption).foregroundStyle(.secondary)
            if let capture = remoteCapture {
                remoteCaptureState(controller, capture)
            } else {
                Menu {
                    ForEach(controller.supportedRubricDevices) { device in
                        Button(device.name) { beginRemote(controller, device: device) }
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
                .font(.caption)
            }
            if let remoteError { Text(remoteError).font(.caption).foregroundStyle(.red) }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func remoteCaptureState(_ controller: DesktopSyncController, _ capture: RubricCaptureRecord) -> some View {
        if let response = capture.response {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: RubricDrawing.inspectorPreview(response.rubric))
                    .resizable().aspectRatio(3, contentMode: .fit).frame(width: 240, height: 80)
                    .accessibilityLabel(L10n.text("Received rubric preview"))
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Review received rubric")).font(.subheadline.weight(.semibold))
                    TextField(L10n.text("Rubric label"), text: $remoteLabel)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button(L10n.text("Save to library")) { saveReceived(controller, capture, response) }
                        Button(L10n.text("Save and insert")) { insertReceived(controller, capture, response) }
                    }
                    if capture.savedLibraryEntryID != nil {
                        HStack(spacing: 10) {
                            Label(L10n.text("Saved in library"), systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                            Button(L10n.text("Request another rubric")) {
                                remoteTask?.cancel()
                                remoteCapture = nil
                                remoteLabel = ""
                                remoteError = nil
                                remoteCreating = false
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        } else if let state = capture.request?.state, [.rejected, .cancelled, .expired].contains(state) {
            HStack {
                Label(L10n.format("The rubric request was %@.", stateLabel(state)), systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Request again")) { remoteCapture = nil; remoteError = nil }
            }
        } else if remoteCreating {
            HStack {
                ProgressView().controlSize(.small)
                Text(L10n.text("Sending rubric request…"))
            }
        } else if capture.request == nil {
            HStack {
                Label(L10n.text("The request was saved but not confirmed. Retry to continue the same request."),
                      systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Retry")) { retryRemote(controller, capture: capture) }
            }
        } else {
            HStack {
                ProgressView().controlSize(.small)
                Text(L10n.format("Waiting for %@ to draw the rubric…", capture.targetDeviceName))
                Spacer()
                if remoteError != nil {
                    Button(L10n.text("Retry")) { pollRemote(controller, requestID: capture.id) }
                } else {
                    Button(L10n.text("Cancel request")) { cancelRemote(controller, requestID: capture.id) }
                }
            }
        }
    }

    private func beginRemote(_ controller: DesktopSyncController, device: PairedDevice) {
        remoteError = nil; remoteTask?.cancel()
        let requestID = UUID()
        do {
            let capture = try controller.prepareRubricCapture(requestID: requestID,
                targetDeviceID: device.id, targetDeviceName: device.name,
                labelHint: label.isEmpty ? nil : label, documentURL: request.documentURL,
                source: request.source, fieldID: request.fieldID)
            remoteCapture = capture
            remoteLabel = capture.labelHint ?? label
            startRemote(controller, capture: capture)
        } catch {
            remoteError = error.localizedDescription
        }
    }

    private func retryRemote(_ controller: DesktopSyncController, capture: RubricCaptureRecord) {
        remoteError = nil
        remoteTask?.cancel()
        startRemote(controller, capture: capture)
    }

    private func startRemote(_ controller: DesktopSyncController, capture: RubricCaptureRecord) {
        remoteCreating = true
        remoteTask = Task { @MainActor in
            do {
                let updated = try await controller.beginRubricCapture(requestID: capture.id,
                    targetDeviceID: capture.targetDeviceID, targetDeviceName: capture.targetDeviceName,
                    labelHint: capture.labelHint, documentURL: capture.documentURL,
                    source: request.source, fieldID: capture.fieldID)
                remoteCapture = updated
                remoteCreating = false
                if let response = updated.response { remoteLabel = response.label }
                else { remoteLabel = updated.labelHint ?? label }
                if updated.response == nil { pollRemote(controller, requestID: updated.id) }
            } catch {
                remoteCreating = false
                remoteError = error.localizedDescription
            }
        }
    }

    private func pollRemote(_ controller: DesktopSyncController, requestID: UUID) {
        remoteTask?.cancel()
        remoteTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    let capture = try await controller.refreshRubricCapture(requestID: requestID)
                    remoteCapture = capture
                    if let response = capture.response {
                        remoteLabel = response.label
                        return
                    }
                    if let state = capture.request?.state, [.rejected, .cancelled, .expired].contains(state) { return }
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    remoteError = error.localizedDescription
                    return
                }
            }
        }
    }

    private func cancelRemote(_ controller: DesktopSyncController, requestID: UUID) {
        remoteTask?.cancel()
        remoteTask = Task { @MainActor in
            do { remoteCapture = try await controller.cancelRubricCapture(requestID: requestID) }
            catch { remoteError = error.localizedDescription }
        }
    }

    private func saveReceived(_ controller: DesktopSyncController, _ capture: RubricCaptureRecord, _ response: RubricResponse) {
        guard let saveRemote, let entryID = saveRemote(capture, remoteLabel) else {
            remoteError = L10n.text("The rubric could not be saved. Try again."); return
        }
        do { remoteCapture = try controller.markRubricCaptureSaved(requestID: capture.id, libraryEntryID: entryID) }
        catch { remoteError = error.localizedDescription }
    }

    private func insertReceived(_ controller: DesktopSyncController, _ capture: RubricCaptureRecord, _ response: RubricResponse) {
        guard let completeRemote, completeRemote(capture, remoteLabel) else {
            remoteError = L10n.text("The document changed while the rubric was away. Save it to the library instead."); return
        }
        if let entryID = saveRemote?(capture, remoteLabel) {
            do { remoteCapture = try controller.markRubricCaptureSaved(requestID: capture.id, libraryEntryID: entryID) }
            catch { remoteError = error.localizedDescription }
        }
        dismiss()
    }

    private func stateLabel(_ state: RubricRequestState) -> String {
        switch state {
        case .rejected: L10n.text("rejected")
        case .cancelled: L10n.text("cancelled")
        case .expired: L10n.text("expired")
        default: L10n.text("finished")
        }
    }
    private var inkColor: String {
        RubricDrawing.hex(NSColor(color))
    }
}

private struct RubricCanvas: NSViewRepresentable {
    @Binding var rubric: LeonardoRubric
    let color: String
    let width: Double
    let style: LeonardoInkStyle
    func makeNSView(context: Context) -> InkCanvasView { InkCanvasView() }
    func updateNSView(_ view: InkCanvasView, context: Context) {
        view.rubric = rubric; view.color = color; view.inkWidth = width; view.style = style
        view.changed = { rubric = $0 }; view.needsDisplay = true
    }
}

private final class InkCanvasView: NSView {
    var rubric = LeonardoRubric()
    var color = "#000000"
    var inkWidth = 3.0
    var style = LeonardoInkStyle.solid
    var changed: ((LeonardoRubric) -> Void)?
    private var stroke: LeonardoInkStroke?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        var current = rubric
        if let stroke { current.strokes.append(stroke) }
        RubricDrawing.draw(current, in: bounds)
    }
    override func mouseDown(with event: NSEvent) {
        guard rubric.strokes.count < 256, rubric.strokes.reduce(0, { $0 + $1.points.count }) < 19000 else { return }
        window?.makeFirstResponder(self)
        stroke = .init(color: color, width: inkWidth, style: style, points: [point(event)])
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard stroke != nil, (stroke?.points.count ?? 0) < 1000 else { return }
        stroke?.points.append(point(event)); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard var completed = stroke else { return }
        completed.points.append(point(event)); rubric.strokes.append(completed); stroke = nil
        changed?(rubric); needsDisplay = true
    }
    private func point(_ event: NSEvent) -> LeonardoInkPoint {
        let location = convert(event.locationInWindow, from: nil)
        return .init(x: min(600, max(0, location.x * 600 / bounds.width)), y: min(200, max(0, location.y * 200 / bounds.height)))
    }
}
