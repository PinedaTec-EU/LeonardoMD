import Foundation

public enum ProjectSearchQuery {
    /// Returns nil for ordinary search and an empty tag for malformed filters.
    static func tagValue(_ query: String) -> String? {
        guard query.lowercased().hasPrefix("tag:") else { return nil }
        let raw = String(query.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("\"") {
            return (try? JSONDecoder().decode(String.self, from: Data(raw.utf8))) ?? ""
        }
        if raw.hasPrefix("'"), raw.hasSuffix("'"), raw.count >= 2 {
            return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        guard !raw.contains(where: { $0.isWhitespace }) else { return "" }
        return raw
    }

    public static func query(forTag tag: String) -> String {
        let data = try? JSONEncoder().encode(tag)
        let quoted = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return "tag:" + quoted
    }
}
