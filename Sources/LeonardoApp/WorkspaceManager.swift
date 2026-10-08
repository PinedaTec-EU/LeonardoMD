import SwiftUI
import AppKit
import LeonardoCore

struct WorkspaceManager: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L10n.text("Workspace")).font(.title2.bold())
                Spacer()
                Button(L10n.text("Done")) { dismiss() }
            }
            Text(session.workspaceURL?.path ?? L10n.text("Select a root folder")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("Select / create folder…")) { session.chooseWorkspace() }
                Button(L10n.text("New project…")) { session.createProject() }.disabled(session.workspaceURL == nil)
            }
            List(session.workspaceProjects) { project in
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(session.accentColor)
                    Button(project.name) { Task { await session.openProject(project.rootURL); dismiss() } }
                    Spacer()
                    Menu {
                        Button(L10n.text("Rename…")) { session.renameProject(project) }
                        Button(L10n.text("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([project.rootURL]) }
                        Button(L10n.text("Delete…"), role: .destructive) { session.deleteProject(project) }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton)
                }.padding(.vertical, 6)
            }
            if session.workspaceProjects.isEmpty { Text(L10n.text("Each subfolder is a local project. Create one to get started.")).foregroundStyle(.secondary) }
            if !session.globalPreferences.recentWorkspacePaths.isEmpty {
                Text(L10n.text("Recent workspaces")).font(.headline)
                ForEach(session.globalPreferences.recentWorkspacePaths.prefix(5), id: \.self) { url in
                    Button(url.lastPathComponent) { Task { await session.openWorkspace(url) } }
                }
            }
        }.buttonStyle(PremiumButtonStyle(compact: true)).padding(24).frame(width: 640, height: 540)
    }
}

extension AppSession {
    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.text("Use as workspace")
        presentFilePanel(panel) { [weak self] url in Task { await self?.openWorkspace(url) } }
    }
    func openWorkspace(_ url: URL) async {
        await initialize()
        do {
            workspaceURL = try await files.openWorkspace(at: url)
            globalPreferences.recentWorkspacePaths.removeAll { $0 == url }
            globalPreferences.recentWorkspacePaths.insert(url, at: 0)
            globalPreferences.recentWorkspacePaths = Array(globalPreferences.recentWorkspacePaths.prefix(12))
            persistSettings()
            await refreshWorkspace()
            showWorkspace = true
        } catch { report(error) }
    }
    func refreshWorkspace() async {
        guard let root = workspaceURL else { return }
        do { workspaceProjects = try await files.projects(in: root) }
        catch { if showWorkspace { report(error) } }
    }
    func createProject() {
        guard let root = workspaceURL, let name = prompt(title: L10n.text("New project"), initial: L10n.text("My project")) else { return }
        Task {
            do {
                let project = try await files.createProject(named: name, in: root)
                await refreshWorkspace()
                await openProject(project.rootURL)
                showWorkspace = false
            } catch { report(error) }
        }
    }
    func renameProject(_ project: ProjectDescriptor) {
        guard let name = prompt(title: L10n.text("Rename project"), initial: project.name) else { return }
        Task { await renameProject(project, to: name) }
    }
    func renameProject(_ project: ProjectDescriptor, to name: String) async {
        guard let workspace = workspaceURL, await prepareNavigation(), await prepareRelatedFileOperation?(project.rootURL) ?? true else { return }
        do {
            let renamed = try await files.renameProject(project, to: name, in: workspace)
            if projectURL == project.rootURL {
                projectURL = renamed.rootURL
                git = GitRepository(rootURL: renamed.rootURL)
                resetSearch()
            }
            await updateMovedDocument(from: project.rootURL, to: renamed.rootURL)
            await relatedPathMoved?(project.rootURL, renamed.rootURL)
            await refreshTree()
            globalPreferences.recentProjectPaths = globalPreferences.recentProjectPaths.map { $0 == project.rootURL ? renamed.rootURL : $0 }
            persistSettings()
            updateTitle()
            await refreshWorkspace()
        } catch { report(error) }
    }
    func deleteProject(_ project: ProjectDescriptor) {
        let alert = NSAlert()
        alert.messageText = L10n.format("Delete project %@?", project.name)
        alert.informativeText = L10n.text("The entire folder and its contents will be deleted from disk.")
        alert.addButton(withTitle: L10n.text("Cancel"))
        alert.addButton(withTitle: L10n.text("Delete"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task { await deleteConfirmedProject(project) }
    }
    func deleteConfirmedProject(_ project: ProjectDescriptor) async {
        guard await prepareNavigation(), await prepareRelatedFileOperation?(project.rootURL) ?? true else { return }
        do {
            try await files.deleteProject(project)
            if projectURL == project.rootURL {
                projectURL = nil
                git = nil
                projectConfiguration = .default
                projectBaseline = .default
                rootEntries = []
                focus = false
                resetSearch()
            }
            if let current = documentURL,
               current == project.rootURL || current.path.hasPrefix(project.rootURL.path + "/") {
                documentURL = nil
                snapshot = nil
                content = ""
                requestedLine = nil
                editorScroll = 0
                externalConflict = false
                saveStatus = "Local file"
            }
            relatedPathDeleted?(project.rootURL)
            updateTitle()
            globalPreferences.recentProjectPaths.removeAll { $0 == project.rootURL }
            persistSettings()
            await refreshWorkspace()
        } catch { report(error) }
    }
}
