import SwiftUI
import AppKit
import LeonardoCore

struct GraphicInspector: View {
    @Bindable var session: AppSession
    let graphic: LeonardoGraphic
    @State private var invalidValue = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L10n.text("Object inspector"), systemImage: "info.circle").font(.headline)
                Spacer()
                Button { session.showsGraphicInspector = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("Close inspector"))
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identity
                    Divider()
                    Text(L10n.text("Position and size")).font(.headline)
                    integer("Page", value: graphic.page, range: 1...999) { $0.page = $1 }
                    metric("X", value: graphic.x) { $0.x = $1 }
                    metric("Y", value: graphic.y) { $0.y = $1 }
                    metric("Width", value: graphic.width) { item, value in
                        item.height = graphic.height * value / graphic.width; item.width = value
                    }
                    metric("Height", value: graphic.height) { item, value in
                        item.width = graphic.width * value / graphic.height; item.height = value
                    }
                    Label(L10n.text("Proportions stay linked"), systemImage: "link")
                        .font(.caption).foregroundStyle(.secondary)
                    integer("Z", value: graphic.z, range: -10000...10000) { $0.z = $1 }
                    Divider()
                    Text(L10n.text("Stacking order")).font(.headline)
                    HStack {
                        Button(L10n.text("Bring forward")) { update { $0.z = min(10000, graphic.z + 1) } }
                        Button(L10n.text("Send backward")) { update { $0.z = max(-10000, graphic.z - 1) } }
                    }
                    HStack {
                        Button(L10n.text("In front of text")) { update { $0.z = max(1, graphic.z) } }
                        Button(L10n.text("Behind text")) { update { $0.z = min(-1, graphic.z) } }
                    }
                    if let rubric = graphic.rubric {
                        Divider()
                        ColorPicker(L10n.text("Ink color"), selection: inkColor, supportsOpacity: false)
                            .accessibilityIdentifier("graphic-ink-color")
                        if Set(rubric.strokes.map(\.color)).count > 1 {
                            Text(L10n.text("Mixed ink colors")).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(L10n.text("Changes all strokes in this inserted copy. Your library stays unchanged."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if invalidValue {
                        Text(L10n.text("Invalid values or the object changed. Select it again and retry."))
                            .font(.caption).foregroundStyle(.red)
                    }
                    Divider()
                    Button(L10n.text("Delete object"), role: .destructive) { session.removeInspectedGraphic(graphic) }
                }.padding(20).disabled(!session.canEditGraphics)
            }
        }
        .frame(width: 320).frame(maxHeight: .infinity, alignment: .top).background(.regularMaterial)
        .accessibilityIdentifier("graphic-inspector")
        .onExitCommand { session.clearGraphicSelection() }
        .onChange(of: graphic.id) { _, _ in invalidValue = false }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(graphic.label, systemImage: graphic.rubric == nil ? "photo" : "signature").font(.headline)
            if let rubric = graphic.rubric {
                Image(nsImage: RubricDrawing.inspectorPreview(rubric))
                    .resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel(L10n.text("Rubric preview"))
            }
        }
    }

    private func metric(_ label: String, value: Double, change: @escaping (inout LeonardoGraphic, Double) -> Void) -> some View {
        HStack {
            Text(L10n.text(label)); Spacer()
            TextField(L10n.text(label), value: Binding(get: { value }, set: { value in update { change(&$0, value) } }),
                      format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: 110).multilineTextAlignment(.trailing)
                .accessibilityIdentifier("graphic-" + label.lowercased())
            Text("pt").font(.caption).foregroundStyle(.secondary).frame(width: 16)
        }
    }

    private func integer(_ label: String, value: Int, range: ClosedRange<Int>, change: @escaping (inout LeonardoGraphic, Int) -> Void) -> some View {
        HStack {
            Text(L10n.text(label)); Spacer()
            TextField(L10n.text(label), value: Binding(get: { value }, set: { value in
                guard range.contains(value) else { invalidValue = true; return }
                update { change(&$0, value) }
            }), format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(width: 110).multilineTextAlignment(.trailing)
                .accessibilityIdentifier("graphic-" + label.lowercased())
            Color.clear.frame(width: 16, height: 1).accessibilityHidden(true)
        }
    }

    private func update(_ change: (inout LeonardoGraphic) -> Void) {
        invalidValue = !session.updateInspectedGraphic(graphic, change: change)
    }

    private var inkColor: Binding<Color> {
        Binding(get: { Color(nsColor: RubricDrawing.color(graphic.rubric?.strokes.first?.color ?? "#000000")) }, set: {
            invalidValue = !session.recolorInspectedGraphic(graphic, color: RubricDrawing.hex(NSColor($0)))
        })
    }
}
