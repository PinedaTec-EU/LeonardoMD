import Foundation
import LeonardoCore

public typealias MarkdownDocument = LeonardoCore.MarkdownDocument
public typealias MarkdownDocumentParser = LeonardoCore.MarkdownDocumentParser

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
                : URL(fileURLWithPath: baseURL.path, isDirectory: true)
        }
        guard !baseURL.absoluteString.hasSuffix("/") else { return baseURL }
        return URL(string: baseURL.absoluteString + "/") ?? baseURL
    }
}
