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
                        Button(L10n.text("Move to Trash…"), role: .destructive) { session.deleteProject(project) }
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
        guard !stopped, !isClosing else { return }
        fileOperationCount += 1
        defer { fileOperationCount -= 1 }
        await initialize()
        do {
            try await authorizePath(url, .directory)
            let opened = try await files.openWorkspace(at: url)
            guard !stopped else { return }
            await refreshFavoriteAssociations()
            guard !stopped, !isClosing else { return }
            workspaceURL = opened
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
        do {
            let include = try await entryFilter(root)
            let projects = try await files.projects(in: root)
            guard !stopped, workspaceURL == root else { return }
            workspaceProjects = projects.filter { include($0.rootURL, true) }
        }
        catch { if showWorkspace { report(error) } }
    }
    func createProject() {
        guard let root = workspaceURL else { return }
        let identity = SessionFileOperationIdentity(sourceURL: root, session: self)
        Task {
            guard identity.isCurrent(in: self), let name = await prompt(title: L10n.text("New project"), initial: L10n.text("My project")) else { return }
            guard identity.isCurrent(in: self) else { return }
            fileOperationCount += 1
            defer { fileOperationCount -= 1 }
            do {
                try await authorizePath(root.appendingPathComponent(name), .directoryMutation)
                guard identity.isCurrent(in: self) else { return }
                let project = try await files.createProject(named: name, in: root)
                await refreshWorkspace()
                await openProject(project.rootURL)
                showWorkspace = false
            } catch { report(error) }
        }
    }
    @discardableResult
    func renameProject(_ project: ProjectDescriptor) -> Task<Void, Never> {
        let identity = SessionFileOperationIdentity(sourceURL: project.rootURL, session: self)
        return Task {
            guard identity.isCurrent(in: self),
                  let name = await prompt(title: L10n.text("Rename project"), initial: project.name),
                  identity.isCurrent(in: self) else { return }
            await renameProject(project, to: name)
        }
    }
    func renameProject(_ project: ProjectDescriptor, to name: String) async {
        let identity = SessionFileOperationIdentity(sourceURL: project.rootURL, session: self)
        guard let workspace = workspaceURL, identity.isCurrent(in: self),
              await prepareNavigation(), await prepareRelatedFileOperation?(project.rootURL) ?? true,
              identity.isCurrent(in: self) else { return }
        fileOperationCount += 1
        defer { fileOperationCount -= 1 }
        do {
            try await authorizePath(project.rootURL, .directoryMutation)
            guard identity.isCurrent(in: self) else { return }
            try await authorizePath(workspace.appendingPathComponent(name), .directoryMutation)
            guard identity.isCurrent(in: self) else { return }
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
    @discardableResult
    func deleteProject(_ project: ProjectDescriptor) -> Task<Void, Never> {
        let identity = SessionFileOperationIdentity(sourceURL: project.rootURL, session: self)
        return Task {
            guard identity.isCurrent(in: self) else { return }
            let alert = NSAlert()
            alert.messageText = L10n.format("Move project %@ to Trash?", project.name)
            alert.informativeText = L10n.text("The entire project folder and its contents will be moved to Trash. You can recover them from Trash.")
            alert.addButton(withTitle: L10n.text("Cancel"))
            alert.addButton(withTitle: L10n.text("Move to Trash"))
            guard await NativeDialog.present(alert, on: presentationWindow) == .alertSecondButtonReturn,
                  identity.isCurrent(in: self) else { return }
            await deleteConfirmedProject(project)
        }
    }
    func deleteConfirmedProject(_ project: ProjectDescriptor) async {
        let identity = SessionFileOperationIdentity(sourceURL: project.rootURL, session: self)
        guard identity.isCurrent(in: self), await prepareNavigation(),
              await prepareRelatedFileOperation?(project.rootURL) ?? true,
              identity.isCurrent(in: self) else { return }
        fileOperationCount += 1
        defer { fileOperationCount -= 1 }
        do {
            try await authorizePath(project.rootURL, .directoryMutation)
            guard identity.isCurrent(in: self) else { return }
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
