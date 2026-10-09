#if os(macOS)
import AppKit
import SwiftUI
import LeonardoSync

struct DesktopGitReviewView: View {
    @Bindable var controller: DesktopGitController
    let value: DesktopGitReview
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var decisions: [String: ReconciliationChoice] = [:]

    private var differences: [ReconciliationDifference] { value.differences }
    private var difference: ReconciliationDifference? { differences.first { $0.path == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Review Git publication")).font(.title2.bold())
            Text(value.branch).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Text(L10n.format("Project ID: %@", value.proposal.publication.projectID.uuidString))
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Text(L10n.format("Device ID: %@", value.proposal.publication.deviceID.uuidString))
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Text(L10n.format("Proposal commit: %@", value.commitID))
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Text(L10n.format("Base %@", value.base.revision)).font(.system(.caption, design: .monospaced))
            Text(L10n.format("Scope: %@", value.scope.folder.isEmpty ? L10n.text("Repository root") : value.scope.folder))
                .font(.system(.caption, design: .monospaced))
            Text(L10n.format("Publication purpose: %@", L10n.text(value.proposal.publication.purpose.desktopLocalizedLabelKey)))
                .foregroundStyle(.secondary)
            Text(L10n.text("Choose incoming, the local draft, deletion, or a custom result for every changed file. Nothing is written until you apply the decisions."))
                .font(.caption)
            HSplitView {
                List(differences, id: \.path, selection: $selected) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.path).lineLimit(2)
                        if entry.hasConflict { Text(L10n.text("Conflict")).font(.caption).foregroundStyle(.orange) }
                        if decisions[entry.path] != nil {
                            Text(L10n.text("Decision selected")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.tag(entry.path)
                }.frame(minWidth: 180, idealWidth: 240, maxWidth: 320)
                if let difference {
                    detail(difference)
                } else {
                    Text(L10n.text("No changes")).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let error = controller.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(decisions.count)/\(differences.count)").monospacedDigit().foregroundStyle(.secondary)
                Button(L10n.text("Apply decisions")) {
                    Task {
                        if await controller.apply(decisions: decisions) { dismiss() }
                    }
                }.disabled(decisions.count != differences.count || controller.busy)
            }
        }
        .padding(24)
        .frame(minWidth: 920, idealWidth: 1_020, minHeight: 600, idealHeight: 700)
        .disabled(controller.busy)
        .interactiveDismissDisabled(controller.busy)
        .onAppear { selected = differences.first?.path }
    }

    @ViewBuilder private func detail(_ difference: ReconciliationDifference) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(difference.path).font(.headline).textSelection(.enabled)
            HStack {
                decision(L10n.text("Use incoming"), .remote, path: difference.path)
                decision(L10n.text("Keep local draft"), .local, path: difference.path)
                decision(L10n.text("Delete file"), .delete, path: difference.path)
                if isTextPath(difference.path) {
                    Button(L10n.text("Edit custom")) {
                        let initial = difference.local?.content ?? difference.remote?.content ?? Data()
                        decisions[difference.path] = .content(initial)
                    }
                }
            }
            if case .content(let bytes) = decisions[difference.path], isTextPath(difference.path) {
                TextEditor(text: Binding(get: {
                    if case .content(let current) = decisions[difference.path] {
                        return String(data: current, encoding: .utf8) ?? ""
                    }
                    return String(data: bytes, encoding: .utf8) ?? ""
                }, set: { decisions[difference.path] = .content(Data($0.utf8)) }))
                    .font(.system(.caption, design: .monospaced)).frame(height: 150)
            }
            HStack(alignment: .top) {
                version(L10n.text("Base"), difference.base)
                version(L10n.text("Local"), difference.local)
                version(L10n.text("Incoming"), difference.remote)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func decision(_ title: String, _ choice: ReconciliationChoice, path: String) -> some View {
        Button {
            decisions[path] = choice
        } label: {
            Label(title, systemImage: decisions[path] == choice ? "checkmark.circle.fill" : "circle")
        }
    }

    @ViewBuilder private func version(_ title: String, _ file: CorpusFile?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold())
            if let file {
                if file.isUnsavedBuffer {
                    Text(L10n.text("Unsaved draft")).font(.caption).foregroundStyle(.orange)
                }
                if isTextPath(file.path), let text = String(data: file.content, encoding: .utf8) {
                    DesktopGitReviewDocumentText(text: text)
                } else {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.content.count), countStyle: .file))
                    if let image = NSImage(data: file.content) {
                        Image(nsImage: image).resizable().scaledToFit()
                    }
                }
            } else {
                Text(L10n.text("Deleted"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func isTextPath(_ path: String) -> Bool {
        ["md", "markdown", "txt"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}

private struct DesktopGitReviewDocumentText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let editor = NSTextView()
        editor.isEditable = false
        editor.isSelectable = true
        editor.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
    }
}
#endif
