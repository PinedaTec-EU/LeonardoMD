import AppKit
import SwiftUI
import Observation
import LeonardoCore
import LeonardoRender
import OSLog

@MainActor @Observable
final class AppSession {
    var workspaceURL: URL?
    var workspaceProjects: [ProjectDescriptor] = []
    var showWorkspace = false
    var documentURL: URL?
    var projectURL: URL?
    var content = ""
    var mode: DocumentMode = .preview
    var focus = false
    var showInspector = false
    var showPreferences = false
    var showGit = false
    var showHidden = false
    var showFrontmatter = UserDefaults.standard.bool(forKey: "showFrontmatter")
    var confirmExternalLinks = UserDefaults.standard.object(forKey: "confirmExternalLinks") as? Bool ?? true
    var pendingExternalURL: URL?
    var errorMessage: String?
    var externalConflict = false
    var busy = false
    var saving = false
    var saveStatus = "Local file"
    var editorScroll = 0.0
    var requestedLine: Int?
    var rootEntries: [NavigationEntry] = []
    var treeRevision = 0
    var searchQuery = ""
    var searchResults: [SearchResult] = []
    var searching = false
    var globalPreferences = GlobalPreferences.default
    var projectConfiguration = ProjectConfiguration.default
    var gitSummary = "Git"
    var prepareRelatedFileOperation: ((URL) async -> Bool)?
    var relatedPathMoved: ((URL, URL) async -> Void)?
    var relatedPathDeleted: ((URL) -> Void)?
    var activateExistingDocument: ((URL, Int?) -> Bool)?
    var openDroppedDocuments: (([URL]) async -> Void)?
    var updateWindow: ((String, URL?, Bool) -> Void)?
    let documents = DocumentStore()
    let files = LocalProjectRepository()
    let configurations = ConfigurationStore.shared
    var globalBaseline = GlobalPreferences.default
    var projectBaseline = ProjectConfiguration.default
    var settingsTask: Task<Void, Never>?
    var settingsRevision = 0
    var git: GitRepository?
    var gitStatus: GitStatus?
    var gitHistory: [GitCommit] = []
    var gitBusy = false
    let renderer = MarkdownPreviewController()
    var snapshot: DocumentSnapshot?
    var saveTask: Task<Void, Never>?
    var searchTask: Task<Void, Never>?
    var monitorTask: Task<Void, Never>?
    var initialized = false
    var initializationTask: Task<Void, Never>?
    var stopped = false
    let globalPreferencesURL: URL
    @ObservationIgnored let openSystemURL: @MainActor (URL) -> Void
    static let readableDocumentExtensions: Set<String> = ["md", "markdown", "txt"]

    init(
        preferencesURL: URL = AppSession.preferencesURL,
        openSystemURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        globalPreferencesURL = preferencesURL
        self.openSystemURL = openSystemURL
    }

    let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "session")

    var presentation: PresentationMode { PresentationMode(projectURL: projectURL, focus: focus, inspectorRequested: showInspector) }
    var isDirty: Bool { snapshot != nil && content != snapshot?.content }
    var wordCount: Int { content.split { $0.isWhitespace }.count }
    var recentProjects: [URL] { globalPreferences.recentProjectPaths }
    var resolved: ResolvedPreferences { projectURL == nil ? ProjectConfiguration.default.resolved(using: globalPreferences) : projectConfiguration.resolved(using: globalPreferences) }
    var features: MarkdownFeatures { resolved.markdown }
    var gitEnabled: Bool { projectURL != nil && projectConfiguration.git.enabled }
    var palette: PaletteDefinition {
        let requested = resolved.paletteDefinition
        return requested.contrastReport.isValid ? requested : PaletteCatalog.definition(for: resolved.palette)
    }
    var darkPalette: Bool { PaletteCatalog.contrastRatio("#FFFFFF", palette.tokens.surface) > PaletteCatalog.contrastRatio("#000000", palette.tokens.surface) }
    var accentColor: Color { Color(hex: palette.tokens.accent) }
    var surfaceColor: Color { Color(hex: palette.tokens.surface) }
    var headings: [(line: Int, title: String)] {
        var fence: Character?
        return content.components(separatedBy: "\n").enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                guard let marker = trimmed.first else { return nil }
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
                return nil
            }
            guard fence == nil else { return nil }
            let prefix = line.prefix { $0 == "#" }
            guard (1...6).contains(prefix.count), line.dropFirst(prefix.count).first == " " else { return nil }
            let title = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : (index + 1, title)
        }
    }
    static var preferencesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeonardoMD/preferences.json")
    }

    func initialize() async {
        if let initializationTask { await initializationTask.value; return }
        guard !initialized else { return }
        let task = Task { [self] in
            do {
                globalPreferences = try await configurations.loadGlobalPreferences(at: globalPreferencesURL)
                globalBaseline = globalPreferences
                showHidden = globalPreferences.showHiddenFiles
            } catch { report(error) }
        }
        initializationTask = task
        await task.value
        initializationTask = nil
        initialized = true
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, !self.stopped else { return }
                await self.checkExternalChanges()
            }
        }
    }

    func open(_ url: URL) async {
        await initialize()
        if activateExistingDocument?(url, nil) == true { return }
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
            await openProject(url)
        } else {
            guard await prepareNavigation() else { return }
            projectURL = nil
            projectConfiguration = .default
            projectBaseline = .default
            rootEntries = []
            resetSearch()
            focus = false
            await openDocument(url)
        }
    }

    func openDocument(_ url: URL, line: Int? = nil) async {
        if activateExistingDocument?(url, line) == true { return }
        let started = ContinuousClock.now
        guard Self.readableDocumentExtensions.contains(url.pathExtension.lowercased()) else {
            openSystemURL(url)
            return
        }
        guard await prepareNavigation() else { return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let loaded = try await documents.read(url)
            guard !stopped else { return }
            documentURL = url
            snapshot = loaded
            content = loaded.content
            editorScroll = 0
            mode = line == nil ? DocumentMode(rawValue: resolved.defaultMode.rawValue) ?? .preview : .edit
            requestedLine = line
            externalConflict = false
            saveStatus = "Saved · local file"
            updateTitle()
            let elapsed = started.duration(to: .now).components
            let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
            logger.info("document_opened duration_ms=\(milliseconds, privacy: .public) bytes=\(loaded.content.utf8.count, privacy: .public)")
        } catch { report(error) }
    }

    func contentChanged() {
        guard snapshot != nil else { return }
        saveStatus = isDirty ? "Cambios pendientes" : L10n.text("Saved · local file")
        updateTitle()
        saveTask?.cancel()
        guard isDirty, !externalConflict else { return }
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            await self?.save()
        }
    }

    func save() async {
        guard !saving, isDirty, let snapshot, let url = documentURL, !externalConflict else { return }
        saving = true
        saveStatus = "Saving…"
        let draft = content
        logger.info("document_save_started")
        do {
            self.snapshot = try await documents.save(draft, to: url, expectedFingerprint: snapshot.fingerprint)
            saveStatus = isDirty ? "Cambios pendientes" : L10n.text("Saved · local file")
            logger.info("document_save_completed")
        } catch DocumentStoreError.conflict {
            externalConflict = true
            saveStatus = "External conflict · edits protected"
        } catch { report(error) }
        saving = false
        updateTitle()
        if isDirty && !externalConflict { contentChanged() }
    }

    func prepareNavigation(allowGitOperation: Bool = false) async -> Bool {
        guard !gitBusy || allowGitOperation else {
            errorMessage = L10n.text("Wait for this project's Git operation to finish before switching documents.")
            return false
        }
        while let pending = settingsTask { await pending.value }
        saveTask?.cancel()
        // Wait for a current autosave to finish before changing the document identity.
        while saving { try? await Task.sleep(for: .milliseconds(20)) }
        await save()
        if isDirty {
            if externalConflict { errorMessage = L10n.text("Resolve the external change by reloading or saving a copy before opening another document.") }
            return false
        }
        return true
    }

    func reloadFromDisk() async {
        guard let url = documentURL else { return }
        if isDirty {
            let alert = NSAlert()
            alert.messageText = L10n.text("Discard your edits and reload the file?")
            alert.addButton(withTitle: L10n.text("Reload"))
            alert.addButton(withTitle: L10n.text("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let previousContent = content
        do {
            let loaded = try await documents.read(url)
            guard documentURL == url else { return }
            guard content == previousContent else {
                externalConflict = true
                saveStatus = "External conflict · edits protected"
                return
            }
            snapshot = loaded
            content = loaded.content
            externalConflict = false
            saveStatus = "Saved · local file"
            updateTitle()
        } catch { externalConflict = true; report(error) }
    }

    func checkExternalChanges() async {
        if settingsTask == nil { do {
            let preferences = try await configurations.loadGlobalPreferences(at: globalPreferencesURL)
            if settingsTask == nil {
                globalPreferences = preferences
                globalBaseline = preferences
                showHidden = preferences.showHiddenFiles
            }
            if let root = projectURL {
                let project = try await configurations.loadProjectConfiguration(for: root)
                if settingsTask == nil, projectURL == root { projectConfiguration = project; projectBaseline = project }
            }
        } catch { logger.error("preferences_refresh_failed") } }
        if workspaceURL != nil { await refreshWorkspace() }
        guard !saving, let snapshot else {
            if projectURL != nil { await refreshTree() }
            return
        }
        var changed = false
        if !externalConflict { changed = await documents.hasChanged(snapshot) }
        guard self.snapshot?.url == snapshot.url, self.snapshot?.fingerprint == snapshot.fingerprint else { return }
        if changed {
            if isDirty { externalConflict = true; saveStatus = "External conflict · edits protected" }
            else { await reloadFromDisk() }
        }
        if projectURL != nil { await refreshTree() }
    }

    func stop() {
        stopped = true
        pendingExternalURL = nil
        saveTask?.cancel()
        searchTask?.cancel()
        monitorTask?.cancel()
    }
    func report(_ error: Error) {
        errorMessage = String(describing: error)
        logger.error("operation_failed category=\(String(reflecting: type(of: error)), privacy: .public)")
    }
    func updateTitle() { updateWindow?(documentURL?.lastPathComponent ?? projectURL?.lastPathComponent ?? "LeonardoMD", documentURL, isDirty) }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}
