import Foundation

/// Keeps ordinary Markdown metadata out of the MDLF prose without inventing
/// structural schema properties or reducing arbitrary YAML to a lossy map.
public enum LeonardoMarkdownMigration {
    public static let frontMatterValueKey = "markdownFrontMatter"

    public static func convert(_ source: String, fallbackTitle: String) -> LeonardoDocument {
        let parts = MarkdownDocumentParser.splitFrontMatter(source)
        let parsed = MarkdownDocumentParser.parse(source)
        let title = parsed.frontMatter["title"].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
        var metadata = LeonardoMetadata(document: LeonardoDocumentDescriptor(title: title))
        if let parts {
            metadata.values[frontMatterValueKey] = .string(parts.header)
        }
        return LeonardoDocument(body: parts?.body ?? source, metadata: metadata)
    }

    public static func previewMetadata(for document: LeonardoDocument) -> MarkdownDocument {
        if case let .string(header) = document.metadata.values[frontMatterValueKey] {
            return MarkdownDocumentParser.parse(header)
        }
        let title = document.metadata.document.title.map { ["title": $0] } ?? [:]
        return MarkdownDocument(body: "", frontMatter: title)
    }
}
