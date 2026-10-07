import Foundation

public struct MarkdownDocument: Equatable, Sendable {
    public let body: String
    public let frontMatter: [String: String]

    public init(body: String, frontMatter: [String: String] = [:]) {
        self.body = body
        self.frontMatter = frontMatter
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
        return MarkdownDocument(body: body, frontMatter: parseMetadata(metadataLines))
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

enum MarkdownURLResolver {
    static func resolve(_ rawValue: String, relativeTo baseURL: URL?) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !hasUnsafeScheme(value) else { return nil }

        let relativeBase = value.hasPrefix("#") ? baseURL : directoryBaseURL(baseURL)
        guard let candidate = URL(string: value, relativeTo: relativeBase)?.absoluteURL else {
            return nil
        }
        guard isAllowed(candidate) else { return nil }
        return candidate
    }

    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        return ["http", "https", "mailto", "tel", "file"].contains(scheme)
    }

    private static func hasUnsafeScheme(_ value: String) -> Bool {
        let lowercased = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return lowercased.hasPrefix("javascript:")
            || lowercased.hasPrefix("vbscript:")
            || lowercased.hasPrefix("data:")
            || lowercased.hasPrefix("blob:")
    }

    private static func directoryBaseURL(_ baseURL: URL?) -> URL? {
        guard let baseURL else { return nil }
        if baseURL.isFileURL {
            return baseURL.hasDirectoryPath || !baseURL.pathExtension.isEmpty
                ? baseURL
                : baseURL.appendingPathComponent("", isDirectory: true)
        }
        guard !baseURL.absoluteString.hasSuffix("/") else { return baseURL }
        return URL(string: baseURL.absoluteString + "/") ?? baseURL
    }
}
