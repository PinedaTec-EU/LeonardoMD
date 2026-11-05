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
            DocumentToolbar(session: session)
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
        .modifier(ExtensionRecommendationPresenter(session: session, isActiveTab: isActiveTab))
        .modifier(SessionAppearance(session: session))
        .background(session.surfaceColor)
        .sheet(item: $session.rubricRequest) { request in
            RubricEditor(request: request, library: session.rubricLibrary, clearField: request.fieldID.map { field in
                { session.documentURL == request.documentURL && session.updateLeonardoFields(expected: request.source, changes: [field: .null]) != nil }
            }, syncController: DesktopSyncController.shared,
            saveRemote: { capture, label in
                guard let response = capture.response else { return nil }
                return session.saveRubricToLibrary(label: label, rubric: response.rubric, sourceRequestID: capture.id)
            }, completeRemote: { capture, label in
                guard let response = capture.response else { return false }
                guard capture.matchesInsertionContext(documentURL: request.documentURL,
                    source: request.source, fieldID: request.fieldID) else { return false }
                return session.finishRubric(request, label: label, rubric: response.rubric,
                    saveToLibrary: true, sourceRequestID: capture.id)
            }) { label, rubric, save in
                session.finishRubric(request, label: label, rubric: rubric, saveToLibrary: save)
            }.modifier(SessionAppearance(session: session))
        }
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
            if session.showsGraphicInspector, let graphic = session.selectedGraphic {
                Divider()
                GraphicInspector(session: session, graphic: graphic)
            } else if session.presentation.showsInspector {
                Divider()
                DocumentInspector(session: session)
            }
        }
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
