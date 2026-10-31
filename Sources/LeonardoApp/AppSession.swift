import AppKit
import SwiftUI
import Observation
import LeonardoCore
import LeonardoSync
import LeonardoDesktopSync
import LeonardoRender
import OSLog

@MainActor @Observable
final class AppSession {
    var documentURL: URL? { didSet { if documentURL != oldValue { editHistory = DocumentEditHistory(); extensionRecommendations.resetOpening() } } }
    /// The logical document format is independent from the bytes currently
    /// loaded into the editor. For an internally opened `.mdlz`, `documentURL`
    /// points at the extracted `.mdlf`/`.mdlr` while `documentSourceURL`
    /// remains the package shown to the user and used by the window chrome.
    var documentKind: AppDocumentKind = .markdown
    var documentStorage: AppDocumentStorage = .localFile
    var documentSourceURL: URL?
    /// The extracted workspace backing an open MDLZ.  A workspace with a
    /// package URL is temporary and must be discarded when the tab closes;
    /// an explicitly extracted workspace has a nil package URL and belongs to
    /// the user, so it is left in place.
    var packageWorkspace: LeonardoPackageWorkspace?
    let extensionRecommendations: ExtensionRecommendations
    var leonardoFormatWarning = false
    private let formatPreferences = LeonardoFormatPreferences.shared
    var packageOpenPreference: LeonardoPackageOpenPreference {
        get { formatPreferences.packageOpenPreference }
        set { formatPreferences.packageOpenPreference = newValue }
    }
    var migrateMarkdownOnSave: Bool {
        get { formatPreferences.migrateMarkdownOnSave }
        set { formatPreferences.migrateMarkdownOnSave = newValue }
    }
    var projectURL: URL?
    var projectFileTree = ProjectFileTree()
    var openProjectDocumentInTab: ((URL, Int?) async -> Void)?
    private var documentContent = ""
    var content: String {
        get { documentContent }
        set {
            guard !isSyncSuspended || syncUpdatingBuffer else { return }
            documentContent = newValue
            editHistory = DocumentEditHistory()
        }
    }
    var editHistory = DocumentEditHistory()
    var syncUpdatingBuffer = false
    var isSyncSuspended: Bool { NativeReconciliationLease.shared.holds(documentURL) || NativeReconciliationLease.shared.holds(projectURL) }
    var isClosing = false
    var isCapturingPreview = false
    var isProtected = true
    var canEditDocument: Bool { documentURL != nil && !isProtected && !isClosing && !isCapturingPreview && !isSyncSuspended && !busy && !stopped }
    @ObservationIgnored weak var presentationWindow: NSWindow?
    var unsavedChangesDecision: @MainActor (String) async -> UnsavedChangesDecision = { _ in .cancel }
    var confirmDiscardForReload: @MainActor () async -> Bool = { false }
    var hasRelatedFileOperation: @MainActor () -> Bool = { false }

    var mode: DocumentMode = .preview
    var focus = false
    var selectedLeonardoFieldID: String?
    var showInspector = false
    var showPreferences = false
    var showGit = false
    var showAllFiles = false
    var foldersFirst = true
    var fileSortDescending = false
    var colorLeonardoFiles: Bool { projectConfiguration.colorLeonardoFiles ?? globalPreferences.colorLeonardoFiles }
    var showHidden = false
    var showFrontmatter = UserDefaults.standard.bool(forKey: "showFrontmatter")
    var confirmExternalLinks = UserDefaults.standard.object(forKey: "confirmExternalLinks") as? Bool ?? true
    var pendingExternalURL: URL?
    var errorMessage: String?
    var externalConflict = false
    var busy = false
    var saving = false
    var fileOperationCount = 0
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
    var prepareRelatedFileOperation: ((URL) async -> Bool)?
    var relatedPathMoved: ((URL, URL) async -> Void)?
    var relatedPathDeleted: ((URL) -> Void)?
    var activateExistingDocument: ((URL, Int?) -> Bool)?
    var openDroppedDocuments: (([URL]) async -> Void)?
    var updateWindow: ((String, URL?, Bool) -> Void)?
    /// Package opening is supplied by the package transport owner. Keeping the
    /// boundary as a session closure prevents AppSession from knowing whether
    /// the bytes came from a ZIP implementation, a future document provider,
    /// or a user-selected extraction directory.
    var openUserGuide: @MainActor () async -> Void = {}
    var openPackageDocument: @MainActor (URL, LeonardoPackageOpenPreference) async -> Bool = { _, _ in false }
    /// The format owner supplies the canonical MD -> MDLF migration. The app
    /// owns the preference and prompt, but never invents a second serializer.
    var migrateMarkdownDocument: @MainActor () async -> Bool = { false }
    var authorizePath: @MainActor (URL, DesktopPeerPathIntent) async throws -> Void = { url, intent in
        try NativeReconciliationLease.shared.check(url, intent: intent)
        try await DesktopPeerController.shared.authorize(url, intent: intent)
        try NativeReconciliationLease.shared.check(url, intent: intent)
    }
    var entryFilter: @MainActor (URL) async throws -> (@Sendable (URL, Bool) -> Bool) = { url in
        try await DesktopPeerController.shared.entryFilter(in: url)
    }
    let documents = DocumentStore()
    let files: LocalProjectRepository
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
    @ObservationIgnored var pendingDocumentAccesses: [UUID: PendingDocumentAccess] = [:]
    @ObservationIgnored var packageWorkspaceDisposalTask: Task<Void, Never>?
    @ObservationIgnored var pendingPackageWorkspaceDisposals: [(workspace: LeonardoPackageWorkspace, waitForIO: Bool)] = []
    /// Test-only synchronization point for deterministic cancellation coverage.
    /// Production leaves this nil; package transport still checks cancellation
    /// immediately before its archive commit.
    @ObservationIgnored var beforePackageArchiveCommitForTesting: (@Sendable () -> Void)?
    var searchTask: Task<Void, Never>?
    var monitorTask: Task<Void, Never>?
    var initialized = false
    var initializationTask: Task<Void, Never>?
    var stopped = false
    let globalPreferencesURL: URL
    @ObservationIgnored let openSystemURL: @MainActor (URL) -> Void
    static let readableDocumentExtensions: Set<String> = ["md", "markdown", "txt", "mdlf", "mdlr"]
    static let packageDocumentExtensions: Set<String> = ["mdlz"]
    static let supportedDocumentExtensions: Set<String> = readableDocumentExtensions.union(packageDocumentExtensions)

    static func documentKind(for url: URL) -> AppDocumentKind {
        AppDocumentKind.classify(url)
    }

    init(
        preferencesURL: URL = AppSession.preferencesURL,
        files: LocalProjectRepository = LocalProjectRepository(),
        extensionWarningPreferences: ExtensionWarningPreferences = .shared,
        openSystemURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.extensionRecommendations = ExtensionRecommendations(preferences: extensionWarningPreferences)
        self.files = files
        globalPreferencesURL = preferencesURL
        self.openSystemURL = openSystemURL
        let existingAuthorization = authorizePath
        authorizePath = { url, intent in
            // Suspended operations must not acquire path ownership as a side effect.
            try NativeReconciliationLease.shared.check(url, intent: intent)
            // Browsing a workspace does not reserve all its projects. Editing
            // a project reserves its root explicitly in openProject.
            if intent != .directory { try InstancePathOwnership.shared.claim(url) }
            try await existingAuthorization(url, intent)
        }
        unsavedChangesDecision = { [weak self] filename in
            await UnsavedChangesPrompt.show(filename, on: self?.presentationWindow)
        }
        confirmDiscardForReload = { [weak self] in
            await NativeDialog.confirmReload(on: self?.presentationWindow)
        }
    }

    let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "session")

    var presentation: PresentationMode { PresentationMode(projectURL: projectURL, focus: focus, inspectorRequested: showInspector) }
    var isDirty: Bool { snapshot != nil && content != snapshot?.content }
    var wordCount: Int { content.split { $0.isWhitespace }.count }
    var recentProjects: [URL] { globalPreferences.recentProjectPaths }
    var resolved: ResolvedPreferences { resolvedSessionPreferences }
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

    func open(_ url: URL, packagePreference: LeonardoPackageOpenPreference? = nil) async {
        guard !isClosing, !stopped else { return }
        fileOperationCount += 1
        defer { fileOperationCount -= 1 }
        await initialize()
        guard !isClosing, !stopped else { return }
        if activateExistingDocument?(url, nil) == true {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            return
        }
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
            await openDocument(url, packagePreference: packagePreference)
        }
    }

    func openDocument(_ url: URL, line: Int? = nil, packagePreference: LeonardoPackageOpenPreference? = nil) async {
        guard !isClosing, !stopped, !isSyncSuspended else { return }
        let access = beginDocumentAccess(to: url)
        defer { finishDocumentAccess(access) }
        do { try await authorizePath(url, .document) } catch { report(error); return }
        guard documentAccessIsActive(access), !isClosing else { return }
        if activateExistingDocument?(url, line) == true {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            return
        }
        let started = ContinuousClock.now
        let kind = Self.documentKind(for: url)
        guard Self.supportedDocumentExtensions.contains(url.pathExtension.lowercased()) else {
            openSystemURL(url)
            return
        }
        guard await prepareNavigation() else { return }
        guard !busy, !isClosing, documentAccessIsActive(access) else { return }
        // Keep an existing temporary package workspace alive until the next
        // document has loaded successfully. A cancelled package dialog or a
        // failed read must leave the current tab usable.
        let previousPackageWorkspace = packageWorkspace
        if kind == .leonardoPackage {
            busy = true
            defer { busy = false }
            guard await openPackageDocument(url, packagePreference ?? packageOpenPreference) else {
                // The package adapter returns false for both cancellation and
                // a reported transport error. Do not turn a cancelled panel
                // into a new alert; the adapter has already reported errors.
                return
            }
            if let previousPackageWorkspace {
                await disposePackageWorkspace(previousPackageWorkspace)
            }
            return
        }
        busy = true
        defer { busy = false }
        do {
            let loaded = try await documents.read(url)
            guard documentAccessIsActive(access), !isClosing, !isSyncSuspended, !NativeReconciliationLease.shared.holds(url) else { return }
            // A declared Leonardo suffix opts into the versioned parser. Do
            // this before mutating session state so a future or malformed
            // document leaves the currently open tab intact.
            if kind.isLeonardo {
                _ = try LeonardoFormatParser.parse(loaded.content)
            }
            if let previousPackageWorkspace {
                discardPackageWorkspace()
                await waitForPackageWorkspaceDisposal()
                guard documentAccessIsActive(access), !isClosing, !isSyncSuspended else { return }
            }
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            isProtected = true
            documentURL = url
            documentSourceURL = nil
            documentKind = kind
            documentStorage = .localFile
            leonardoFormatWarning = kind == .markdown && Self.containsLeonardoMarkers(loaded.content)
            snapshot = loaded
            content = loaded.content
            editorScroll = 0
            mode = line == nil ? kind.defaultMode(global: resolved.defaultMode) : .edit
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
        guard !stopped, !isSyncSuspended, snapshot != nil else { return }
        saveStatus = isDirty ? "Pending changes" : "Saved · local file"
        updateTitle()
        saveTask?.cancel()
    }

    func prepareNavigation(allowGitOperation: Bool = false) async -> Bool {
        guard !isSyncSuspended else { return false }
        guard !gitBusy || allowGitOperation else {
            errorMessage = L10n.text("Wait for this project's Git operation to finish before switching documents.")
            return false
        }
        while let pending = settingsTask { await pending.value }
        saveTask?.cancel()
        // Wait for a current save to finish before changing the document identity.
        while saving || saveTask != nil { try? await Task.sleep(for: .milliseconds(20)) }
        guard await flushPreviewEdits(), await resolveUnsavedChanges() else { return false }
        if isDirty {
            if externalConflict { errorMessage = L10n.text("Resolve the external change by reloading or saving a copy before opening another document.") }
            return false
        }
        return true
    }


    func stop() {
        stopped = true
        pendingExternalURL = nil
        saveTask?.cancel()
        discardPackageWorkspace()
        searchTask?.cancel()
        monitorTask?.cancel()
    }
    func report(_ error: Error) {
        if error is InstancePathOwnership.InUse {
            errorMessage = L10n.text("This document or project is in use by another LeonardoMD instance. Close that instance before opening it here.")
        } else if case DesktopRuntimeError.busy = error {
            errorMessage = L10n.text("Synchronization is applying changes. Try again when it finishes.")
        } else if let syncError = error as? SyncError, syncError == .outsideScope {
            errorMessage = L10n.text("This item is outside the content selected on the source Mac.")
        } else if let syncError = error as? SyncError, syncError == .revoked {
            errorMessage = L10n.text("Access to this linked copy was revoked.")
        } else { errorMessage = String(describing: error) }
        logger.error("operation_failed category=\(String(reflecting: type(of: error)), privacy: .public)")
    }
    func updateTitle() {
        updateWindow?(displayDocumentURL?.lastPathComponent ?? projectURL?.lastPathComponent ?? "LeonardoMD", displayDocumentURL, isDirty)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}
