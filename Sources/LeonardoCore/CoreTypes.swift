import Foundation

// MARK: - Workspace and project model

public struct ProjectDescriptor: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let rootURL: URL

    public init(name: String, rootURL: URL) {
        self.name = name
        self.rootURL = rootURL.standardizedFileURL
        self.id = self.rootURL.path
    }
}

public enum FileNodeKind: String, Codable, Hashable, Sendable {
    case folder
    case markdown
    case image
    case file
}

public struct FileNode: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let relativePath: String
    public let url: URL
    public let kind: FileNodeKind
    public let isHidden: Bool

    public var isDirectory: Bool { kind == .folder }

    public init(
        name: String,
        relativePath: String,
        url: URL,
        kind: FileNodeKind,
        isHidden: Bool
    ) {
        self.name = name
        self.relativePath = relativePath
        self.url = url.standardizedFileURL
        self.id = self.relativePath
        self.kind = kind
        self.isHidden = isHidden
    }
}

public struct SearchMatch: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let relativePath: String
    public let lineNumber: Int?
    public let column: Int?
    public let snippet: String
    public let matchedInFileName: Bool

    public init(
        url: URL,
        relativePath: String,
        lineNumber: Int?,
        column: Int?,
        snippet: String,
        matchedInFileName: Bool
    ) {
        self.url = url.standardizedFileURL
        self.relativePath = relativePath
        self.lineNumber = lineNumber
        self.column = column
        self.snippet = snippet
        self.matchedInFileName = matchedInFileName
        self.id = "\(relativePath):\(lineNumber ?? 0):\(column ?? 0):\(matchedInFileName)"
    }
}

public struct MarkdownFeatures: Codable, Hashable, Sendable {
    public var mermaidEnabled: Bool
    public var mathEnabled: Bool
    public var defaultMode: MarkdownMode

    public init(
        mermaidEnabled: Bool = false,
        mathEnabled: Bool = false,
        defaultMode: MarkdownMode = .preview
    ) {
        self.mermaidEnabled = mermaidEnabled
        self.mathEnabled = mathEnabled
        self.defaultMode = defaultMode
    }

    enum CodingKeys: String, CodingKey {
        case mermaidEnabled
        case mathEnabled
        case defaultMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mermaidEnabled = try container.decodeIfPresent(Bool.self, forKey: .mermaidEnabled) ?? false
        mathEnabled = try container.decodeIfPresent(Bool.self, forKey: .mathEnabled) ?? false
        defaultMode = try container.decodeIfPresent(MarkdownMode.self, forKey: .defaultMode) ?? .preview
    }
}

public enum GitSyncMode: String, Codable, CaseIterable, Hashable, Sendable {
    case manual
}

public struct GitProjectConfiguration: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var syncMode: GitSyncMode

    public init(enabled: Bool = false, syncMode: GitSyncMode = .manual) {
        self.enabled = enabled
        self.syncMode = syncMode
    }
}

public struct ProjectConfiguration: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var name: String?
    public var palette: PaletteID?
    public var customTokens: PaletteTokenOverrides?
    public var paperEffect: PaperEffect?
    public var git: GitProjectConfiguration
    public var markdown: MarkdownFeatures?

    public var defaultMode: MarkdownMode {
        get { markdown?.defaultMode ?? .preview }
        set {
            var features = markdown ?? MarkdownFeatures()
            features.defaultMode = newValue
            markdown = features
        }
    }

    public init(
        schemaVersion: Int = ProjectConfiguration.currentSchemaVersion,
        name: String? = nil,
        palette: PaletteID? = nil,
        customTokens: PaletteTokenOverrides? = nil,
        paperEffect: PaperEffect? = nil,
        git: GitProjectConfiguration = GitProjectConfiguration(),
        markdown: MarkdownFeatures? = nil,
        defaultMode: MarkdownMode = .preview
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.palette = palette
        self.customTokens = customTokens
        self.paperEffect = paperEffect
        self.git = git
        if let markdown {
            self.markdown = markdown
        } else if defaultMode != .preview {
            var features = MarkdownFeatures()
            features.defaultMode = defaultMode
            self.markdown = features
        } else {
            self.markdown = nil
        }
    }

    public static let `default` = ProjectConfiguration()

    public func resolved(using global: GlobalPreferences) -> ResolvedPreferences {
        let selectedPalette = palette ?? global.palette
        var tokens = PaletteCatalog.definition(for: selectedPalette).tokens
        if palette == nil, let globalCustomTokens = global.customTokens {
            tokens = globalCustomTokens.applying(to: tokens)
        }
        if let customTokens {
            tokens = customTokens.applying(to: tokens)
        }
        return ResolvedPreferences(
            palette: selectedPalette,
            paletteTokens: tokens,
            paperEffect: paperEffect ?? global.paperEffect,
            markdown: markdown ?? global.markdown,
            defaultMode: markdown?.defaultMode ?? global.markdown.defaultMode,
            showHiddenFiles: global.showHiddenFiles
        )
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case name
        case palette
        case customTokens
        case paperEffect
        case git
        case markdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version > 0, version <= Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(version)
        }
        schemaVersion = version
        name = try container.decodeIfPresent(String.self, forKey: .name)
        palette = try container.decodeIfPresent(PaletteID.self, forKey: .palette)
        customTokens = try container.decodeIfPresent(PaletteTokenOverrides.self, forKey: .customTokens)
        paperEffect = try container.decodeIfPresent(PaperEffect.self, forKey: .paperEffect)
        git = try container.decodeIfPresent(GitProjectConfiguration.self, forKey: .git) ?? GitProjectConfiguration()
        markdown = try container.decodeIfPresent(MarkdownFeatures.self, forKey: .markdown)
    }
}

public struct GlobalPreferences: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var palette: PaletteID
    public var customTokens: PaletteTokenOverrides?
    public var paperEffect: PaperEffect
    public var markdown: MarkdownFeatures
    public var showHiddenFiles: Bool
    public var recentWorkspacePaths: [URL]
    public var recentProjectPaths: [URL]

    public init(
        schemaVersion: Int = GlobalPreferences.currentSchemaVersion,
        palette: PaletteID = .paperWhite,
        customTokens: PaletteTokenOverrides? = nil,
        paperEffect: PaperEffect = .white,
        markdown: MarkdownFeatures = MarkdownFeatures(),
        showHiddenFiles: Bool = false,
        recentWorkspacePaths: [URL] = [],
        recentProjectPaths: [URL] = []
    ) {
        self.schemaVersion = schemaVersion
        self.palette = palette
        self.customTokens = customTokens
        self.paperEffect = paperEffect
        self.markdown = markdown
        self.showHiddenFiles = showHiddenFiles
        self.recentWorkspacePaths = recentWorkspacePaths
        self.recentProjectPaths = recentProjectPaths
    }

    public static let `default` = GlobalPreferences()

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case palette
        case customTokens
        case paperEffect
        case markdown
        case showHiddenFiles
        case recentWorkspacePaths
        case recentProjectPaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version > 0, version <= Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(version)
        }
        schemaVersion = version
        palette = try container.decodeIfPresent(PaletteID.self, forKey: .palette) ?? .paperWhite
        customTokens = try container.decodeIfPresent(PaletteTokenOverrides.self, forKey: .customTokens)
        paperEffect = try container.decodeIfPresent(PaperEffect.self, forKey: .paperEffect) ?? .white
        markdown = try container.decodeIfPresent(MarkdownFeatures.self, forKey: .markdown) ?? MarkdownFeatures()
        showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        recentWorkspacePaths = try container.decodeIfPresent([URL].self, forKey: .recentWorkspacePaths) ?? []
        recentProjectPaths = try container.decodeIfPresent([URL].self, forKey: .recentProjectPaths) ?? []
    }
}

public struct ResolvedPreferences: Hashable, Sendable {
    public let palette: PaletteID
    public let paletteTokens: PaletteTokens
    public let paperEffect: PaperEffect
    public let markdown: MarkdownFeatures
    public let defaultMode: MarkdownMode
    public let showHiddenFiles: Bool

    public var paletteDefinition: PaletteDefinition {
        PaletteDefinition(
            id: palette,
            displayName: PaletteCatalog.definition(for: palette).displayName,
            tokens: paletteTokens
        )
    }

    public init(
        palette: PaletteID,
        paletteTokens: PaletteTokens? = nil,
        paperEffect: PaperEffect,
        markdown: MarkdownFeatures,
        defaultMode: MarkdownMode,
        showHiddenFiles: Bool
    ) {
        self.palette = palette
        self.paletteTokens = paletteTokens ?? PaletteCatalog.definition(for: palette).tokens
        self.paperEffect = paperEffect
        self.markdown = markdown
        self.defaultMode = defaultMode
        self.showHiddenFiles = showHiddenFiles
    }
}

// MARK: - Errors

public enum ConfigurationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidJSON
    case missingConfigurationDirectory
}

public enum FileSystemRepositoryError: Error, Equatable, Sendable {
    case workspaceDoesNotExist(URL)
    case workspaceIsNotDirectory(URL)
    case projectDoesNotExist(URL)
    case projectIsNotDirectory(URL)
    case projectNotInWorkspace(URL)
    case pathEscapesProject
    case invalidName(String)
    case itemAlreadyExists(URL)
    case cannotDeleteProjectRoot
    case cannotMoveIntoDescendant
}

public enum DocumentStoreError: Error, Sendable {
    case fileNotFound(URL)
    case unsupportedEncoding(URL)
    case conflict(expected: FileFingerprint, current: DocumentSnapshot?)
    case invalidDestination(URL)
}

public enum GitError: Error, Equatable, Sendable {
    case noRepository(URL)
    case commandFailed(arguments: [String], exitCode: Int32, message: String)
    case workingTreeDirty
    case mergeConflict([String])
    case invalidPath(String)
    case invalidCommitMessage
}
