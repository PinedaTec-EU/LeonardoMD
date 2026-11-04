import SwiftUI
import AppKit
import LeonardoCore

struct RubricEditor: View {
    let request: RubricRequest
    let complete: (String, LeonardoRubric, Bool) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var rubric = LeonardoRubric()
    @State private var label = ""
    @State private var color = Color.black
    @State private var width = 3.0
    @State private var style = LeonardoInkStyle.solid
    @State private var saveToLibrary = true
    @State private var library = RubricLibrary.shared
    @State private var error: String?

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
            TextField(L10n.text("Rubric label"), text: $label).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("rubric-label")
            HStack {
                ColorPicker(L10n.text("Color"), selection: $color, supportsOpacity: false)
                Text(L10n.text("Stroke width"))
                Slider(value: $width, in: 0.5...24).frame(width: 100)
                Text(width, format: .number.precision(.fractionLength(1))).monospacedDigit()
                Picker(L10n.text("Stroke style"), selection: $style) {
                    Text(L10n.text("Solid")).tag(LeonardoInkStyle.solid)
                    Text(L10n.text("Brush")).tag(LeonardoInkStyle.brush)
                }.frame(width: 150)
            }
            RubricCanvas(rubric: $rubric, color: inkColor, width: width, style: style)
                .frame(width: 600, height: 200).background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("Insert rubric")) {
                    if complete(label, rubric, request.savesToLibrary || saveToLibrary) { dismiss() }
                    else { error = L10n.text("The rubric could not be inserted. Check the document and try again.") }
                }.disabled(!rubric.isValid || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || label.count > 120)
            }
        }.padding(24).frame(width: 648)
    }
    private var inkColor: String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
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
