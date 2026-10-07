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
        guard normalized.hasPrefix("---\n") || normalized == delimiter else {
            return MarkdownDocument(body: normalized)
        }

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first.map(String.init) == delimiter else {
            return MarkdownDocument(body: normalized)
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: {
            $0 == Substring(delimiter) || $0 == Substring(alternateDelimiter)
        }) else {
            return MarkdownDocument(body: normalized)
        }

        let metadataLines = lines[lines.index(after: lines.startIndex)..<closingIndex]
        let bodyStart = lines.index(after: closingIndex)
        let body = lines[bodyStart...].joined(separator: "\n")
        return MarkdownDocument(body: body, frontMatter: parseMetadata(metadataLines), tags: FrontMatterTags.parse(metadataLines.map(String.init)))
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

