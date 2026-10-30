import SwiftUI
import AppKit

struct WorkspaceView: View {
    @Bindable var session: AppSession
    let isActiveTab: Bool

    init(session: AppSession, isActiveTab: Bool = true) {
        self.session = session
        self.isActiveTab = isActiveTab
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if session.presentation.showsSidebar {
                HSplitView {
                    ProjectSidebar(session: session, isActiveTab: isActiveTab)
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 600)
                    workspaceDocument.frame(minWidth: 440)
                }
            } else {
                workspaceDocument
            }
            Divider()
            statusBar
        }
        .modifier(SessionAppearance(session: session))
        .background(session.surfaceColor)
        .sheet(isPresented: $session.showWorkspace) { WorkspaceManager(session: session).modifier(SessionAppearance(session: session)) }
        .sheet(isPresented: $session.showPreferences) { PreferencesView(session: session).modifier(SessionAppearance(session: session)) }
        .sheet(isPresented: $session.showGit) { GitPanel(session: session).modifier(SessionAppearance(session: session)) }
        .alert("LeonardoMD", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button(L10n.text("OK")) { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .confirmationDialog(
            session.pendingExternalURL?.isFileURL == true ? L10n.text("Open file in another application?") : L10n.text("Open external link?"),
            isPresented: Binding(
                get: { session.pendingExternalURL != nil },
                set: { if !$0 { session.cancelExternalOpening() } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.text("Open with the default application")) { session.confirmExternalOpening() }
            Button(L10n.text("Cancel"), role: .cancel) { session.cancelExternalOpening() }
        } message: {
            Text(session.pendingExternalURL?.absoluteString ?? "")
        }
        .onChange(of: session.showFrontmatter) { _, value in UserDefaults.standard.set(value, forKey: "showFrontmatter") }
        .onChange(of: session.confirmExternalLinks) { _, value in UserDefaults.standard.set(value, forKey: "confirmExternalLinks") }
        .onChange(of: session.showHidden) { _, value in
            session.globalPreferences.showHiddenFiles = value
            session.persistSettings()
        }
        .task { await session.initialize() }
    }

    private var workspaceDocument: some View {
        HStack(spacing: 0) {
            documentArea.frame(maxWidth: .infinity, maxHeight: .infinity).disabled(session.busy)
            if session.presentation.showsInspector {
                Divider()
                DocumentInspector(session: session)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu {
                Button(L10n.text("Open document…")) { session.chooseDocument() }
                Button(L10n.text("Open project…")) { session.chooseProject() }
                Button(L10n.text("Workspaces…")) { session.showWorkspace = true }
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
                .font(.caption).foregroundStyle(.secondary)
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
                    Label(L10n.text("Undo"), systemImage: "arrow.uturn.backward")
                }
                .disabled(!session.canUndoDocument)
                .help(L10n.text("Undo") + " (⌘Z)")
                .accessibilityIdentifier("document-undo")
                Button { Task { await session.redoDocument() } } label: {
                    Label(L10n.text("Redo"), systemImage: "arrow.uturn.forward")
                }
                .disabled(!session.canRedoDocument)
                .help(L10n.text("Redo") + " (⇧⌘Z)")
                .accessibilityIdentifier("document-redo")
                Button { Task { await session.save() } } label: {
                    Label(L10n.text("Save"), systemImage: "square.and.arrow.down")
                }
                .disabled(!session.isDirty || session.saving || session.externalConflict || session.isSyncSuspended)
                .help(L10n.text("Save (⌘S)"))
                PremiumSelection(selection: Binding(get: { session.mode }, set: { value in Task { await session.setDocumentMode(value) } }), options: session.availableDocumentModes, title: { $0.title })
                    .accessibilityLabel(L10n.text("Mode"))
                    .accessibilityIdentifier("document-mode")
                Button { session.focus.toggle() } label: { Image(systemName: session.focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                    .help(session.focus ? L10n.text("Exit focus mode") : L10n.text("Focus mode"))
                    .accessibilityIdentifier("focus-mode")
                Button { session.exportPDF() } label: { Image(systemName: "square.and.arrow.up") }.help(L10n.text("Export PDF"))
                if session.documentKind.isLeonardo {
                    Button { session.exportMarkdown() } label: { Image(systemName: "doc.text") }
                        .help(L10n.text("Export Markdown…"))
                        .accessibilityLabel(L10n.text("Export Markdown…"))
                        .accessibilityIdentifier("export-markdown")
                        .disabled(session.busy || session.isSyncSuspended)
                    Button { session.exportLeonardoPackage() } label: { Image(systemName: "archivebox") }
                        .help(L10n.text("Export Leonardo package"))
                        .accessibilityLabel(L10n.text("Export Leonardo package"))
                        .accessibilityIdentifier("export-leonardo-package")
                }
                if session.documentStorage == .package {
                    Button { session.extractLeonardoPackageToFolder() } label: { Image(systemName: "folder.badge.gearshape") }
                        .help(L10n.text("Extract and work in a folder…"))
                        .accessibilityLabel(L10n.text("Extract and work in a folder…"))
                        .accessibilityIdentifier("extract-leonardo-package")
                        .disabled(session.busy || session.isSyncSuspended)
                }
                if session.leonardoDocument?.isForm == true {
                    Button { session.exportLeonardoResponse() } label: { Image(systemName: "doc.badge.arrow.up") }
                        .help(L10n.text("Export Leonardo response"))
                        .accessibilityLabel(L10n.text("Export Leonardo response"))
                        .accessibilityIdentifier("export-leonardo-response")
                }
            }
            Button { session.showInspector.toggle() } label: { Label(L10n.text("Outline"), systemImage: "list.bullet") }
                .accessibilityIdentifier("document-outline-button")
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder private var documentArea: some View {
        if session.documentURL == nil {
            WelcomeView(session: session)
        } else {
            VStack(spacing: 0) {
                if session.externalConflict {
                    HStack {
                        Label(L10n.text("The file changed outside LeonardoMD. Reload it or save your edits as a copy?"), systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button(L10n.text("Reload")) { Task { await session.reloadFromDisk() } }
                        Button(L10n.text("Save copy…")) { session.saveCopy() }
                    }.padding(12).background(Color.orange.opacity(0.14))
                }
                if session.leonardoFormatWarning {
                    HStack(spacing: 10) {
                        Label(L10n.text("This Markdown contains Leonardo document markers."), systemImage: "doc.badge.gearshape")
                        Spacer()
                        Button(L10n.text("Save as MDLF…")) {
                            Task {
                                if await session.migrateMarkdownNow() { session.leonardoFormatWarning = false }
                            }
                        }
                        Button(L10n.text("Dismiss")) { session.leonardoFormatWarning = false }
                    }
                    .padding(12)
                    .background(session.accentColor.opacity(0.12))
                }
                switch session.mode {
                case .preview: session.preview
                case .edit: editor
                case .split:
                    HSplitView {
                        editor.frame(minWidth: 220)
                        session.preview.frame(minWidth: 220)
                    }
                case .fill: session.preview
                }
            }
        }
    }
    private var editor: some View {
        MarkdownEditor(text: Binding(get: { session.content }, set: { _ = session.editDocument(expected: session.content, replacement: $0) }), scrollFraction: $session.editorScroll, requestedLine: session.requestedLine, usesDocumentHistory: true)
            .id(session.documentURL)
            .disabled(!session.canEditDocument)
    }
    private var statusBar: some View {
        HStack {
            Text(ApplicationUpdates.shared.versionDisplayText)
                .accessibilityIdentifier("status-version")
            Divider().frame(height: 12)
            if session.busy { ProgressView().controlSize(.mini) }
            Label(L10n.text(session.saveStatus), systemImage: session.isDirty ? "circle.fill" : "checkmark.circle")
            Spacer()
            Text(session.focus ? L10n.text("Focus") : session.projectURL == nil ? L10n.text("Standalone document") : L10n.text("Project"))
            Label(session.documentFormatLabel, systemImage: session.documentStatusIcon)
                .foregroundStyle(session.documentStatusColor)
            Label(session.documentStorageLabel, systemImage: session.documentStorageIcon)
                .foregroundStyle(session.documentStorageColor)
            Text("UTF-8")
            Text(L10n.format("%d words", session.wordCount))
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 8)
    }
}
