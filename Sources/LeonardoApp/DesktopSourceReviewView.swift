import AppKit
import SwiftUI
import LeonardoSync

struct DesktopSourceReviewView: View {
    @Bindable var controller: DesktopSyncController
    let value: DesktopSourceReview
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var decisions: [String: ReconciliationChoice] = [:]
    private var differences: [ReconciliationDifference] { value.review.comparison.differences }
    private var difference: ReconciliationDifference? { differences.first { $0.path == selected } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Review incoming changes")).font(.title2.bold())
            Text(value.item.deviceName).foregroundStyle(.secondary)
            Text(L10n.text("Choose a result for every changed file. Nothing is applied until you confirm."))
                .font(.caption)
            HSplitView {
                List(differences, id: \.path, selection: $selected) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.path).lineLimit(2)
                        if entry.hasConflict { Text(L10n.text("Conflict")).font(.caption).foregroundStyle(.orange) }
                        if decisions[entry.path] != nil { Text(L10n.text("Decision selected")).font(.caption).foregroundStyle(.secondary) }
                    }.tag(entry.path)
                }.frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                if let difference {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(difference.path).font(.headline).textSelection(.enabled)
                        HStack {
                            decision(L10n.text("Keep incoming"), .local, path: difference.path)
                            decision(L10n.text("Keep this Mac"), .remote, path: difference.path)
                            decision(L10n.text("Delete file"), .delete, path: difference.path)
                        }
                        if ["md", "markdown", "txt"].contains(URL(fileURLWithPath: difference.path).pathExtension.lowercased()) {
                            Button(L10n.text("Edit merged result")) {
                                let initial = difference.remote?.content ?? difference.local?.content ?? Data()
                                decisions[difference.path] = .content(initial)
                            }
                            if case .content(let bytes) = decisions[difference.path] {
                                TextEditor(text: Binding(get: {
                                    if case .content(let current) = decisions[difference.path] { return String(data: current, encoding: .utf8) ?? "" }
                                    return String(data: bytes, encoding: .utf8) ?? ""
                                }, set: { decisions[difference.path] = .content(Data($0.utf8)) }))
                                    .font(.system(.caption, design: .monospaced)).frame(height: 140)
                            }
                        }
                        HStack(alignment: .top) {
                            version(L10n.text("Base"), difference.base)
                            version(L10n.text("Other Mac"), difference.local)
                            version(L10n.text("This Mac"), difference.remote)
                        }
                    }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else { Text(L10n.text("No changes")).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            if let error = controller.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(decisions.count)/\(differences.count)").monospacedDigit().foregroundStyle(.secondary)
                Button(L10n.text("Apply decisions")) {
                    Task { if await controller.applyReview(value, decisions: decisions) { dismiss() } }
                }.disabled(decisions.count != differences.count)
            }
        }.padding(24).frame(minWidth: 860, idealWidth: 960, minHeight: 560, idealHeight: 660)
            .disabled(controller.busy).interactiveDismissDisabled(controller.busy)
            .onAppear { selected = differences.first?.path }
    }
    private func decision(_ title: String, _ choice: ReconciliationChoice, path: String) -> some View {
        Button { decisions[path] = choice } label: {
            Label(title, systemImage: decisions[path] == choice ? "checkmark.circle.fill" : "circle")
        }
    }
    private func version(_ title: String, _ file: CorpusFile?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold())
            if let file {
                if file.isUnsavedBuffer { Text(L10n.text("Unsaved draft")).font(.caption).foregroundStyle(.orange) }
                if ["md", "markdown", "txt"].contains(URL(fileURLWithPath: file.path).pathExtension.lowercased()),
                   let text = String(data: file.content, encoding: .utf8) {
                    ReviewDocumentText(text: text)
                } else {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.content.count), countStyle: .file))
                    if let image = NSImage(data: file.content) { Image(nsImage: image).resizable().scaledToFit() }
                }
            } else { Text(L10n.text("Deleted")) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// AppKit lays out the selected document in a bounded scroll view instead of one huge SwiftUI Text.
private struct ReviewDocumentText: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        let editor = NSTextView(); editor.isEditable = false; editor.isSelectable = true
        editor.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        editor.isVerticallyResizable = true; editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
    }
}
