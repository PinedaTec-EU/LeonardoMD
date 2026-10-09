import Foundation

/// Controls the capabilities and visual treatment of a Markdown preview.
public struct MarkdownPreviewConfiguration: Equatable, Sendable {
    public var allowsMermaid: Bool
    public var allowsMath: Bool
    public var frontMatter: FrontMatterVisibility
    public var externalLinkPolicy: ExternalLinkPolicy
    public var appearance: MarkdownAppearance
    public var renderDebounce: Duration
    /// Optional project boundary for relative local image assets.
    public var localAssetRoot: URL?
    public var memoryAssets: MarkdownMemoryAssets?
    public var allowsRemoteImages: Bool

    public init(
        allowsMermaid: Bool = false,
        allowsMath: Bool = false,
        frontMatter: FrontMatterVisibility = .hidden,
        externalLinkPolicy: ExternalLinkPolicy = .systemBrowser,
        appearance: MarkdownAppearance = .default,
        renderDebounce: Duration = .milliseconds(80),
        localAssetRoot: URL? = nil,
        memoryAssets: MarkdownMemoryAssets? = nil,
        allowsRemoteImages: Bool = true
    ) {
        self.allowsMermaid = allowsMermaid
        self.allowsMath = allowsMath
        self.frontMatter = frontMatter
        self.externalLinkPolicy = externalLinkPolicy
        self.appearance = appearance
        self.renderDebounce = renderDebounce
        self.localAssetRoot = localAssetRoot
        self.memoryAssets = memoryAssets
        self.allowsRemoteImages = allowsRemoteImages
    }

    public static let `default` = MarkdownPreviewConfiguration()
}

public enum FrontMatterVisibility: Equatable, Sendable {
    case hidden
    case metadata
}

public enum ExternalLinkPolicy: Equatable, Sendable {
    case systemBrowser
    case callbackOnly
    case blocked
}

public enum PaperEffect: String, CaseIterable, Equatable, Sendable {
    case plain
    case ruled
    case grid
    case microgrid
    case parchment
}

/// Hex CSS colors keep appearance values portable between SwiftUI and the web view.
public struct MarkdownAppearance: Equatable, Sendable {
    public var backgroundHex: String
    public var textHex: String
    public var headingHex: String
    public var accentHex: String
    public var codeBackgroundHex: String
    public var paperEffect: PaperEffect

    public init(
        backgroundHex: String,
        textHex: String,
        headingHex: String,
        accentHex: String,
        codeBackgroundHex: String,
        paperEffect: PaperEffect = .plain
    ) {
        self.backgroundHex = backgroundHex
        self.textHex = textHex
        self.headingHex = headingHex
        self.accentHex = accentHex
        self.codeBackgroundHex = codeBackgroundHex
        self.paperEffect = paperEffect
    }

    public static let `default` = MarkdownAppearance(
        backgroundHex: "#F8F8F5",
        textHex: "#171717",
        headingHex: "#2B5C8A",
        accentHex: "#2B5C8A",
        codeBackgroundHex: "#ECECE7"
    )

    public static let leonardoClassic = MarkdownAppearance(
        backgroundHex: "#E7D6AD",
        textHex: "#11100D",
        headingHex: "#7A1114",
        accentHex: "#8C3F22",
        codeBackgroundHex: "#D8C596",
        paperEffect: .parchment
    )
}
