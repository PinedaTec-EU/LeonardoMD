import Foundation

public actor ConfigurationStore {
    /// The process-wide store used by app sessions so settings merges are serialized.
    public static let shared = ConfigurationStore()

    public static let configurationDirectoryName = ".leonardomd"
    public static let projectConfigurationFileName = "project.json"
    public static let localConfigurationFileName = "local.json"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func projectConfigurationURL(for projectRoot: URL) -> URL {
        projectRoot
            .appendingPathComponent(configurationDirectoryName, isDirectory: true)
            .appendingPathComponent(projectConfigurationFileName)
    }

    public static func localConfigurationURL(for projectRoot: URL) -> URL {
        projectRoot
            .appendingPathComponent(configurationDirectoryName, isDirectory: true)
            .appendingPathComponent(localConfigurationFileName)
    }

    public func loadProjectConfiguration(for projectRoot: URL) throws -> ProjectConfiguration {
        let url = Self.projectConfigurationURL(for: projectRoot)
        guard fileManager.fileExists(atPath: url.path) else {
            return .default
        }
        return try decode(ProjectConfiguration.self, from: url)
    }

    public func saveProjectConfiguration(
        _ configuration: ProjectConfiguration,
        for projectRoot: URL
    ) throws {
        guard configuration.schemaVersion > 0,
              configuration.schemaVersion <= ProjectConfiguration.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(configuration.schemaVersion)
        }
        let directory = projectRoot.appendingPathComponent(Self.configurationDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(configuration, to: Self.projectConfigurationURL(for: projectRoot))
    }

    public func loadGlobalPreferences(at fileURL: URL) throws -> GlobalPreferences {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .default
        }
        return try decode(GlobalPreferences.self, from: fileURL)
    }

    public func saveGlobalPreferences(_ preferences: GlobalPreferences, at fileURL: URL) throws {
        guard preferences.schemaVersion > 0,
              preferences.schemaVersion <= GlobalPreferences.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(preferences.schemaVersion)
        }
        try encode(preferences, to: fileURL)
    }

    /// Merges a session snapshot into the latest global preferences and persists it once.
    ///
    /// Only fields changed from `baseline` are applied. This keeps independent settings
    /// changes from stale windows when all callers use the shared actor.
    @discardableResult
    public func mergeGlobalPreferences(
        updated: GlobalPreferences,
        baseline: GlobalPreferences,
        at fileURL: URL
    ) throws -> GlobalPreferences {
        let current = try loadGlobalPreferences(at: fileURL)
        let merged = mergeGlobalPreferences(current: current, updated: updated, baseline: baseline)
        try saveGlobalPreferences(merged, at: fileURL)
        return merged
    }

    /// Merges a session snapshot into the latest project configuration and persists it once.
    ///
    /// Nested Markdown and Git settings are merged per field, so a stale session changing
    /// one feature does not overwrite another session's independent feature change.
    @discardableResult
    public func mergeProjectConfiguration(
        updated: ProjectConfiguration,
        baseline: ProjectConfiguration,
        for projectRoot: URL
    ) throws -> ProjectConfiguration {
        let current = try loadProjectConfiguration(for: projectRoot)
        let merged = mergeProjectConfiguration(current: current, updated: updated, baseline: baseline)
        try saveProjectConfiguration(merged, for: projectRoot)
        return merged
    }

    public func loadLocalPreferences<T: Decodable>(
        _ type: T.Type,
        for projectRoot: URL
    ) throws -> T? {
        let url = Self.localConfigurationURL(for: projectRoot)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decode(type, from: url)
    }

    public func saveLocalPreferences<T: Encodable>(
        _ value: T,
        for projectRoot: URL
    ) throws {
        let directory = projectRoot.appendingPathComponent(Self.configurationDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(value, to: Self.localConfigurationURL(for: projectRoot))
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw ConfigurationError.invalidJSON
        }

        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: [.atomic])

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.invalidJSON
        }
    }

    private func mergeGlobalPreferences(
        current: GlobalPreferences,
        updated: GlobalPreferences,
        baseline: GlobalPreferences
    ) -> GlobalPreferences {
        var merged = current
        if updated.schemaVersion != baseline.schemaVersion {
            merged.schemaVersion = updated.schemaVersion
        }
        if updated.palette != baseline.palette {
            merged.palette = updated.palette
        }
        merged.customTokens = mergePaletteTokenOverrides(
            current: current.customTokens,
            updated: updated.customTokens,
            baseline: baseline.customTokens
        )
        if updated.paperEffect != baseline.paperEffect {
            merged.paperEffect = updated.paperEffect
        }
        merged.markdown = mergeMarkdownFeatures(
            current: current.markdown,
            updated: updated.markdown,
            baseline: baseline.markdown
        )
        if updated.showHiddenFiles != baseline.showHiddenFiles {
            merged.showHiddenFiles = updated.showHiddenFiles
        }
        if updated.recentWorkspacePaths != baseline.recentWorkspacePaths {
            merged.recentWorkspacePaths = updated.recentWorkspacePaths
        }
        if updated.recentProjectPaths != baseline.recentProjectPaths {
            merged.recentProjectPaths = updated.recentProjectPaths
        }
        return merged
    }

    private func mergeProjectConfiguration(
        current: ProjectConfiguration,
        updated: ProjectConfiguration,
        baseline: ProjectConfiguration
    ) -> ProjectConfiguration {
        var merged = current
        if updated.schemaVersion != baseline.schemaVersion {
            merged.schemaVersion = updated.schemaVersion
        }
        if updated.name != baseline.name {
            merged.name = updated.name
        }
        if updated.palette != baseline.palette {
            merged.palette = updated.palette
        }
        merged.customTokens = mergePaletteTokenOverrides(
            current: current.customTokens,
            updated: updated.customTokens,
            baseline: baseline.customTokens
        )
        if updated.paperEffect != baseline.paperEffect {
            merged.paperEffect = updated.paperEffect
        }
        if updated.git.enabled != baseline.git.enabled {
            merged.git.enabled = updated.git.enabled
        }
        if updated.git.syncMode != baseline.git.syncMode {
            merged.git.syncMode = updated.git.syncMode
        }
        merged.markdown = mergeOptionalMarkdownFeatures(
            current: current.markdown,
            updated: updated.markdown,
            baseline: baseline.markdown
        )
        return merged
    }

    private func mergeMarkdownFeatures(
        current: MarkdownFeatures,
        updated: MarkdownFeatures,
        baseline: MarkdownFeatures
    ) -> MarkdownFeatures {
        var merged = current
        if updated.mermaidEnabled != baseline.mermaidEnabled {
            merged.mermaidEnabled = updated.mermaidEnabled
        }
        if updated.mathEnabled != baseline.mathEnabled {
            merged.mathEnabled = updated.mathEnabled
        }
        if updated.defaultMode != baseline.defaultMode {
            merged.defaultMode = updated.defaultMode
        }
        return merged
    }

    private func mergeOptionalMarkdownFeatures(
        current: MarkdownFeatures?,
        updated: MarkdownFeatures?,
        baseline: MarkdownFeatures?
    ) -> MarkdownFeatures? {
        guard updated != baseline else {
            return current
        }
        guard let updated else {
            return nil
        }
        guard let baseline else {
            // Creating an override from no override is an intentional complete value.
            return updated
        }
        var merged = current ?? baseline
        if updated.mermaidEnabled != baseline.mermaidEnabled {
            merged.mermaidEnabled = updated.mermaidEnabled
        }
        if updated.mathEnabled != baseline.mathEnabled {
            merged.mathEnabled = updated.mathEnabled
        }
        if updated.defaultMode != baseline.defaultMode {
            merged.defaultMode = updated.defaultMode
        }
        return merged
    }

    private func mergePaletteTokenOverrides(
        current: PaletteTokenOverrides?,
        updated: PaletteTokenOverrides?,
        baseline: PaletteTokenOverrides?
    ) -> PaletteTokenOverrides? {
        guard updated != baseline else {
            return current
        }
        guard let updated else {
            // Clearing the optional override is an explicit user operation.
            return nil
        }
        guard let baseline else {
            // A newly-created override has no baseline fields to compare against.
            return updated
        }
        var merged = current ?? baseline
        if updated.surface != baseline.surface { merged.surface = updated.surface }
        if updated.text != baseline.text { merged.text = updated.text }
        if updated.heading != baseline.heading { merged.heading = updated.heading }
        if updated.accent != baseline.accent { merged.accent = updated.accent }
        if updated.border != baseline.border { merged.border = updated.border }
        if updated.codeBackground != baseline.codeBackground { merged.codeBackground = updated.codeBackground }
        if updated.quote != baseline.quote { merged.quote = updated.quote }
        return merged
    }
}
