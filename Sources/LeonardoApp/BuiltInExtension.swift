import LeonardoCore

/// The allowlist for recommendations. Document text can never name an arbitrary plugin.
enum BuiltInExtension: String, CaseIterable, Identifiable {
    case mermaid, math
    case charts = "vega-lite"
    case citations
    case extras = "markdown-extensions"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .mermaid: "Mermaid"
        case .math: "Math"
        case .charts: "Charts (Vega-Lite)"
        case .citations: "Citations"
        case .extras: "Markdown extras"
        }
    }
    var flag: WritableKeyPath<MarkdownFeatures, Bool> {
        switch self {
        case .mermaid: \.mermaidEnabled
        case .math: \.mathEnabled
        case .charts: \.vegaLiteEnabled
        case .citations: \.citationsEnabled
        case .extras: \.markdownExtensionsEnabled
        }
    }
}
