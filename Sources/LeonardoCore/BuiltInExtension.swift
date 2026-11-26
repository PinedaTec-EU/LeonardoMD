/// Renderer-owned document extensions shared by macOS and Little Leonardo.
public enum BuiltInExtension: String, CaseIterable, Hashable, Identifiable {
    case mermaid
    case math
    case charts = "vega-lite"
    case citations
    case extras = "markdown-extensions"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mermaid: "Mermaid"
        case .math: "Math"
        case .charts: "Charts (Vega-Lite)"
        case .citations: "Citations"
        case .extras: "Markdown extras"
        }
    }

    public var purpose: String {
        switch self {
        case .mermaid: "Diagrams inside your documents"
        case .math: "Formulas with KaTeX"
        case .charts: "Inline data visualizations inside your documents"
        case .citations: "Bibliographies and references with Citation.js"
        case .extras: "Footnotes and GitHub-style callouts"
        }
    }

    public var flag: WritableKeyPath<MarkdownFeatures, Bool> {
        switch self {
        case .mermaid: \.mermaidEnabled
        case .math: \.mathEnabled
        case .charts: \.vegaLiteEnabled
        case .citations: \.citationsEnabled
        case .extras: \.markdownExtensionsEnabled
        }
    }
}
