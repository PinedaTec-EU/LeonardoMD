import Foundation
import LeonardoCore

/// The on-disk suffix is part of the user's workflow, while the renderer and
/// editor continue to work with one logical document body.  Keep this type in
/// the app layer so opening a normal Markdown file never silently opts into
/// Leonardo's richer document engine.
enum AppDocumentKind: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case leonardoTemplate
    case leonardoResponse
    case leonardoPackage

    var id: Self { self }

    var iconName: String {
        switch self {
        case .markdown: "doc.text"
        case .leonardoTemplate: "doc.richtext"
        case .leonardoResponse: "doc.text.magnifyingglass"
        case .leonardoPackage: "archivebox"
        }
    }

    var isLeonardo: Bool { self != .markdown }
    var supportsFormFilling: Bool { self == .leonardoTemplate || self == .leonardoResponse || self == .leonardoPackage }

    @MainActor func defaultMode(global: MarkdownMode) -> DocumentMode {
        switch self {
        case .leonardoResponse: return .fill
        case .markdown, .leonardoTemplate, .leonardoPackage:
            return DocumentMode(rawValue: global.rawValue) ?? .preview
        }
    }

    static func classify(_ url: URL) -> Self {
        switch url.pathExtension.lowercased() {
        case "mdlf": return .leonardoTemplate
        case "mdlr": return .leonardoResponse
        case "mdlz": return .leonardoPackage
        default: return .markdown
        }
    }

    static func isSupportedExtension(_ extension: String) -> Bool {
        ["md", "markdown", "txt", "mdlf", "mdlr", "mdlz"].contains(extension.lowercased())
    }
}

/// Where the current tab's editable bytes live.  A package opened with the
/// default policy is represented by `.package`; a user-requested extraction is
/// represented by `.extracted`.  The distinction is intentionally visible to
/// the UI because Save has different consequences in each case.
enum AppDocumentStorage: String, CaseIterable, Identifiable, Sendable {
    case localFile
    case package
    case extracted

    var id: Self { self }

    var iconName: String {
        switch self {
        case .localFile: "folder"
        case .package: "archivebox"
        case .extracted: "folder.badge.gearshape"
        }
    }
}

/// Preference used when a `.mdlz` package is opened.  The first option keeps
/// the transport convenience for form recipients; the other two make the
/// extraction decision explicit for people and agents that need ordinary
/// files on disk.
enum LeonardoPackageOpenPreference: String, CaseIterable, Identifiable, Sendable {
    case package
    case ask
    case extracted

    static let defaultsKey = "leonardoPackageOpenPreference"
    static let defaultValue: Self = .package

    var id: Self { self }

    @MainActor var title: String {
        switch self {
        case .package: L10n.text("Open package and save it as a package")
        case .ask: L10n.text("Ask how to open each package")
        case .extracted: L10n.text("Extract into a folder")
        }
    }
}

extension AppSession {
    var displayDocumentURL: URL? { documentSourceURL ?? documentURL }

    var availableDocumentModes: [DocumentMode] {
        var modes: [DocumentMode] = [.preview, .edit, .split]
        if documentKind.supportsFormFilling { modes.append(.fill) }
        return modes
    }

    var documentFormatLabel: String {
        switch documentKind {
        case .markdown: L10n.text("Markdown")
        case .leonardoTemplate: L10n.text("Leonardo document")
        case .leonardoResponse: L10n.text("Leonardo form response")
        case .leonardoPackage: L10n.text("Leonardo package")
        }
    }

    var documentStorageLabel: String {
        switch documentStorage {
        case .localFile: L10n.text("Local file")
        case .package: L10n.text("Package · saves to .mdlz")
        case .extracted: L10n.text("Extracted folder")
        }
    }

    var documentStatusIcon: String { documentKind.iconName }
    var documentStorageIcon: String { documentStorage.iconName }

    static func containsLeonardoMarkers(_ source: String) -> Bool {
        let parsed = MarkdownDocumentParser.parse(source)
        if parsed.frontMatter.contains(where: { key, value in
            let normalizedKey = key.lowercased().replacingOccurrences(of: "_", with: "")
            let normalizedValue = value.lowercased()
            return normalizedKey == "format" && normalizedValue == "leonardo"
                || normalizedKey == "formatversion"
                || normalizedKey == "leonardo"
        }) {
            return true
        }
        return source.range(of: "<!-- leonardo:", options: [.caseInsensitive]) != nil
            || source.range(of: "{{ field:", options: [.caseInsensitive]) != nil
    }

    func requestMarkdownMigration() {
        guard documentKind == .markdown else { return }
        Task { _ = await migrateMarkdownDocument() }
    }

    func migrateMarkdownNow() async -> Bool {
        guard documentKind == .markdown else { return false }
        return await migrateMarkdownDocument()
    }
}

