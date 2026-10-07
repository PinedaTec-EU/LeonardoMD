import SwiftUI
import AppKit
import LeonardoCore

struct WorkspaceManager: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Espacio de trabajo").font(.title2.bold())
                Spacer()
                Button("Listo") { dismiss() }
            }
            Text(session.workspaceURL?.path ?? "Selecciona una carpeta raíz").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Seleccionar / crear carpeta…") { session.chooseWorkspace() }
                Button("Nuevo proyecto…") { session.createProject() }.disabled(session.workspaceURL == nil)
            }
            List(session.workspaceProjects) { project in
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(session.accentColor)
                    Button(project.name) { Task { await session.openProject(project.rootURL); dismiss() } }
                    Spacer()
                    Menu {
                        Button("Renombrar…") { session.renameProject(project) }
                        Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.rootURL]) }
                        Button("Eliminar…", role: .destructive) { session.deleteProject(project) }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton)
                }.padding(.vertical, 6)
            }
            if session.workspaceProjects.isEmpty { Text("Cada subcarpeta es un proyecto local. Crea uno para empezar.").foregroundStyle(.secondary) }
            if !session.globalPreferences.recentWorkspacePaths.isEmpty {
                Text("Espacios recientes").font(.headline)
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
        panel.prompt = "Usar como espacio"
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
        guard let root = workspaceURL, let name = prompt(title: "Nuevo proyecto", initial: "Mi proyecto") else { return }
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
        guard let name = prompt(title: "Renombrar proyecto", initial: project.name) else { return }
        Task { await renameProject(project, to: name) }
    }
    func renameProject(_ project: ProjectDescriptor, to name: String) async {
        guard let workspace = workspaceURL, await prepareNavigation() else { return }
        do {
            let renamed = try await files.renameProject(project, to: name, in: workspace)
            if projectURL == project.rootURL {
                projectURL = renamed.rootURL
                git = GitRepository(rootURL: renamed.rootURL)
                resetSearch()
            }
            await updateMovedDocument(from: project.rootURL, to: renamed.rootURL)
            await refreshTree()
            globalPreferences.recentProjectPaths = globalPreferences.recentProjectPaths.map { $0 == project.rootURL ? renamed.rootURL : $0 }
            persistSettings()
            updateTitle()
            await refreshWorkspace()
        } catch { report(error) }
    }
    func deleteProject(_ project: ProjectDescriptor) {
        let alert = NSAlert()
        alert.messageText = "¿Eliminar el proyecto \(project.name)?"
        alert.informativeText = "Se eliminará toda su carpeta y su contenido del disco."
        alert.addButton(withTitle: "Cancelar")
        alert.addButton(withTitle: "Eliminar")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task { await deleteConfirmedProject(project) }
    }
    func deleteConfirmedProject(_ project: ProjectDescriptor) async {
        guard await prepareNavigation() else { return }
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
                saveStatus = "Archivo local"
            }
            updateTitle()
            globalPreferences.recentProjectPaths.removeAll { $0 == project.rootURL }
            persistSettings()
            await refreshWorkspace()
        } catch { report(error) }
    }
}
