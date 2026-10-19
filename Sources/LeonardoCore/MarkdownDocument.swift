import Foundation

public struct MarkdownDocument: Equatable, Sendable {
    public let body: String
    public let frontMatter: [String: String]
    public let tags: [String]

    public init(body: String, frontMatter: [String: String] = [:], tags: [String] = []) {
        self.body = body
        self.frontMatter = frontMatter
        self.tags = tags
    }
}

public enum MarkdownDocumentParser {
    private static let delimiter = "---"
    private static let alternateDelimiter = "..."

    public static func parse(_ source: String) -> MarkdownDocument {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        guard let parts = splitFrontMatter(normalized) else {
            return MarkdownDocument(body: normalized)
        }
        let metadataLines = parts.metadata.split(separator: "\n", omittingEmptySubsequences: false)[...]
        return MarkdownDocument(body: parts.body, frontMatter: parseMetadata(metadataLines), tags: FrontMatterTags.parse(metadataLines.map(String.init)))
    }

    /// Separates the envelope without normalizing the author's bytes.
    static func splitFrontMatter(_ source: String) -> (header: String, metadata: String, body: String)? {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        guard lines.first == Substring(delimiter),
              let closing = lines.dropFirst().firstIndex(where: {
                  $0 == Substring(delimiter) || $0 == Substring(alternateDelimiter)
              }) else { return nil }
        let end = lines[closing].endIndex
        let bodyStart = end == source.endIndex ? end : source.index(after: end)
        let metadataStart = source.index(after: lines[0].endIndex)
        let metadata = String(source[metadataStart..<lines[closing].startIndex])
        return (String(source[..<bodyStart]), metadata, String(source[bodyStart...]))
    }

    private static func parseMetadata(_ lines: ArraySlice<Substring>) -> [String: String] {
        var values: [String: String] = [:]
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            let rawValue = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            values[String(key)] = unquote(String(rawValue))
        }
        return values
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        let first = value.first
        let last = value.last
        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}

