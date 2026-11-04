import SwiftUI
import LeonardoCore

struct DocumentToolbar: View {
    @Bindable var session: AppSession
    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Button(L10n.text("Open document…")) { session.chooseDocument() }
                Button(L10n.text("Open project…")) { session.chooseProject() }
                if session.projectURL == nil, let url = session.documentURL {
                    Button(L10n.text("Open folder as project")) { Task { await session.openProject(url.deletingLastPathComponent()) } }
                }
                if session.projectURL != nil {
                    Button(L10n.text("View only this document")) { Task { await session.detachProject() } }
                }
                if !session.recentProjects.isEmpty {
                    Divider()
                    ForEach(session.recentProjects, id: \.self) { url in
                        Button(url.lastPathComponent) { Task { await session.openProject(url) } }
                    }
                }
            } label: { Image(systemName: "folder").padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1))).shadow(color: .black.opacity(0.08), radius: 3, y: 2) }.menuStyle(.borderlessButton).frame(width: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                Text(session.displayDocumentURL?.lastPathComponent ?? "LeonardoMD").font(.headline).lineLimit(1)
                    if session.isDirty {
                        Label(L10n.text("Unsaved changes"), systemImage: "circle.fill")
                            .font(.caption.weight(.semibold))
                            .accessibilityIdentifier("document-unsaved-changes")
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: session.documentStatusIcon).foregroundStyle(session.documentStatusColor)
                    Text(session.documentFormatLabel).foregroundStyle(session.documentStatusColor)
                    Text("·")
                    Image(systemName: session.documentStorageIcon).foregroundStyle(session.documentStorageColor)
                    Text(session.documentStorageLabel).foregroundStyle(session.documentStorageColor)
                    if let location = session.documentLocationLabel {
                        Text("·")
                        Text(location).foregroundStyle(session.documentStorageColor).lineLimit(1)
                    }
                    if session.projectURL != nil {
                        Text("·")
                        Text(session.projectURL!.lastPathComponent)
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if session.documentURL != nil {
                Button { Task { await session.toggleProtection() } } label: {
                    Image(systemName: session.isProtected ? "lock.fill" : "lock.open")
                        .opacity(session.isProtected ? 1 : 0.5)
                }
                .help(L10n.text(session.isProtected ? "Protected · click to enable editing" : "Writable · click to protect"))
                .accessibilityLabel(L10n.text("Document protection"))
                .accessibilityValue(L10n.text(session.isProtected ? "Read only" : "Writable"))
                .accessibilityIdentifier("document-protection")
                .disabled(session.isSyncSuspended || session.busy)
                Button { Task { await session.undoDocument() } } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!session.canUndoDocument)
                .help(L10n.text("Undo") + " (⌘Z)")
                .accessibilityIdentifier("document-undo")
                Button { Task { await session.redoDocument() } } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!session.canRedoDocument)
                .help(L10n.text("Redo") + " (⇧⌘Z)")
                .accessibilityIdentifier("document-redo")
                Button { Task { await session.save() } } label: {
                    Label(L10n.text("Save"), systemImage: "square.and.arrow.down")
                }
                .disabled(!session.isDirty || session.saving || session.externalConflict || session.isSyncSuspended)
                .help(L10n.text("Save (⌘S)"))
                Menu {
                    ForEach(session.availableDocumentModes, id: \.self) { mode in
                        Button(modeLabel(mode)) { Task { await session.setDocumentMode(mode) } }
                    }
                } label: { menuTitle(modeLabel(session.mode)) }
                .accessibilityLabel(L10n.text("Mode"))
                .accessibilityIdentifier("document-mode")
                .accessibilityValue(modeLabel(session.mode))
                .fixedSize()
                insertionMenu
                exportMenu
                Menu {
                    Button(L10n.text(session.focus ? "Exit focus mode" : "Focus mode")) { session.focus.toggle() }
                    Button(L10n.text("Outline")) { session.showInspector.toggle() }
                    Menu(L10n.text("Objects")) {
                        ForEach(session.leonardoDocument?.metadata.layout?.objects ?? []) { object in
                            Button(object.label) { session.renderer.selectObject(object.id) }
                        }
                    }.disabled(!session.canEditGraphics || session.mode == .edit)
                } label: { menuTitle(L10n.text("More")) }
                .fixedSize()
            }
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
    }


    private func menuTitle(_ title: String) -> some View {
        HStack(spacing: 5) { Text(title).lineLimit(1); Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true) }
            .accessibilityElement(children: .combine)
    }

    private func modeLabel(_ mode: DocumentMode) -> String {
        switch mode {
        case .preview: return L10n.text("Previsualize")
        case .edit: return L10n.text("Edit source")
        case .split: return L10n.text("Split view")
        case .fill: return L10n.text("Fill")
        }
    }

    private var insertionMenu: some View {
        Menu {
            if session.documentKind.isLeonardo {
                Button(L10n.text("Image…")) { session.chooseGraphicImage() }.disabled(!session.canEditGraphics)
                Divider()
                ForEach(session.rubricLibrary.entries) { entry in
                    Button { _ = session.insertGraphic(.init(label: entry.label, rubric: entry.rubric)) } label: {
                        Label { Text(entry.label) } icon: { Image(nsImage: RubricDrawing.thumbnail(entry.rubric)) }
                    }.disabled(!session.canEditGraphics)
                }
                Button(L10n.text("New rubric…")) { session.requestRubric() }.disabled(!session.canEditGraphics)
                Button(L10n.text("Page break")) { session.insertPageBreak() }.disabled(!session.canEditGraphics)
            } else {
                Button(L10n.text("Save as MDLF…")) { Task { _ = await session.migrateMarkdownNow() } }
                    .disabled(!session.canEditGraphics)
            }
        } label: { menuTitle(L10n.text("Insert")) }
        .fixedSize().accessibilityIdentifier("document-insert")
    }

    private var exportMenu: some View {
        Menu {
            Button(L10n.text("Export PDF")) { session.exportPDF() }
            if session.documentKind.isLeonardo {
                Button(L10n.text("Export Markdown…")) { session.exportMarkdown() }
                Button(L10n.text("Export Leonardo package")) { session.exportLeonardoPackage() }
            }
            if session.documentStorage == .package {
                Button(L10n.text("Extract and work in a folder…")) { session.extractLeonardoPackageToFolder() }
            }
            if session.leonardoDocument?.isForm == true {
                Button(L10n.text("Export Leonardo response")) { session.exportLeonardoResponse() }
            }
        } label: { menuTitle(L10n.text("Export")) }
        .fixedSize().disabled(session.busy || session.isSyncSuspended)
        .accessibilityIdentifier("document-export")
    }
}
