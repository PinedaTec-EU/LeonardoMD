import SwiftUI
import AppKit

struct WorkspaceView: View {
    @Bindable var session: AppSession
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                if session.presentation.showsSidebar {
                    ProjectSidebar(session: session)
                    Divider()
                }
                documentArea.frame(maxWidth: .infinity, maxHeight: .infinity).disabled(session.busy)
                if session.presentation.showsInspector {
                    Divider()
                    DocumentInspector(session: session)
                }
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
                Text(session.documentURL?.lastPathComponent ?? "LeonardoMD").font(.headline).lineLimit(1)
                Text(session.projectURL == nil ? L10n.text("Document viewer") : session.projectURL!.lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if session.documentURL != nil {
                PremiumSelection(selection: $session.mode, options: DocumentMode.allCases, title: { $0.title })
                    .accessibilityLabel(L10n.text("Mode"))
                    .accessibilityIdentifier("document-mode")
                Button { session.focus.toggle() } label: { Image(systemName: session.focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                    .help(session.focus ? L10n.text("Exit focus mode") : L10n.text("Focus mode"))
                    .accessibilityIdentifier("focus-mode")
                Button { session.exportPDF() } label: { Image(systemName: "square.and.arrow.up") }.help(L10n.text("Export PDF"))
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
            VStack(spacing: 18) {
                Image(systemName: "doc.richtext").font(.system(size: 54, weight: .light)).foregroundStyle(session.accentColor)
                Text(L10n.text("Your documents, your way.")).font(.largeTitle.weight(.semibold))
                Text(L10n.text("Open a Markdown file to read it instantly\nor a folder to work with a project."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("Open document…")) { session.chooseDocument() }.buttonStyle(PremiumButtonStyle(prominent: true))
                    Button(L10n.text("Open project…")) { session.chooseProject() }.buttonStyle(PremiumButtonStyle())
                }
                Button(L10n.text("Manage workspaces…")) { session.showWorkspace = true }.buttonStyle(PremiumButtonStyle())
                Text(L10n.text("Local · No account · Optional extensions")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { WelcomeWatermark() }
        } else {
            VStack(spacing: 0) {
                if session.externalConflict {
                    HStack {
                        Label(L10n.text("The file changed outside LeonardoMD. Your edits are protected."), systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button(L10n.text("Reload")) { Task { await session.reloadFromDisk() } }
                        Button(L10n.text("Save copy…")) { session.saveCopy() }
                    }.padding(12).background(Color.orange.opacity(0.14))
                }
                switch session.mode {
                case .preview: session.preview
                case .edit: editor
                case .split:
                    HSplitView {
                        editor.frame(minWidth: 220)
                        session.preview.frame(minWidth: 220)
                    }
                }
            }
        }
    }
    private var editor: some View {
        MarkdownEditor(text: $session.content, scrollFraction: $session.editorScroll, requestedLine: session.requestedLine)
            .id(session.documentURL)
            .onChange(of: session.content) { _, _ in session.contentChanged() }
    }
    private var statusBar: some View {
        HStack {
            if session.busy { ProgressView().controlSize(.mini) }
            Label(L10n.text(session.saveStatus), systemImage: session.isDirty ? "circle.fill" : "checkmark.circle")
            Spacer()
            Text(session.focus ? L10n.text("Focus") : session.projectURL == nil ? L10n.text("Standalone document") : L10n.text("Project"))
            Text("Markdown · UTF-8")
            Text(L10n.format("%d words", session.wordCount))
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 8)
    }
}
