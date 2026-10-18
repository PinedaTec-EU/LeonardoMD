import CryptoKit
import Foundation

/// Rewrites only resource references in the exported copy. Originals are never modified.
enum LeonardoPortableResources {
    struct Collection {
        var content: String
        var assets: [LeonardoZIPArchive.Entry]
    }

    static func collect(content: String, documentURL: URL) throws -> Collection {
        let base = documentURL.deletingLastPathComponent()
        var assets: [String: Data] = [:]
        var mapping: [String: String] = [:]
        func portable(_ reference: String) throws -> String {
            guard !reference.isEmpty, !reference.hasPrefix("#") else { return reference }
            if let scheme = URL(string: reference)?.scheme, scheme != "file" { return reference }
            if let existing = mapping[reference] { return existing }
            let decoded = reference.removingPercentEncoding ?? reference
            let url: URL
            if reference.hasPrefix("file:"), let fileURL = URL(string: reference) { url = fileURL }
            else if decoded.hasPrefix("/") { url = URL(fileURLWithPath: decoded) }
            else { url = base.appendingPathComponent(decoded) }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let size = values?.fileSize,
                  size <= LeonardoZIPArchive.maximumArchiveBytes / 2 else { throw LeonardoPackageError.missingAsset(reference) }
            let bytes = try Data(contentsOf: url)
            let hash = SHA256.hash(data: bytes).prefix(8).map { String(format: "%02x", $0) }.joined()
            let suffix = url.pathExtension.lowercased().filter { $0.isASCII && $0.isLetter || $0.isNumber }
            let name = "assets/\(hash)\(suffix.isEmpty ? "" : "." + suffix)"
            assets[name] = bytes
            mapping[reference] = name
            return name
        }
        // Markdown inline images (including angle-bracket destinations) and reference definitions.
        var result = content
        let expressions = [
            #"!\[[^\]\n]*\]\(\s*<?([^\s)>]+)>?(?:\s+["'][^\n]*?["'])?\s*\)"#,
            #"(?m)^\s{0,3}\[[^\]\n]+\]:\s*<?([^\s>]+)>?"#,
            #"(?i)<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#
        ]
        for expression in expressions {
            let regex = try NSRegularExpression(pattern: expression)
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range(at: 1), in: result) else { continue }
                let replacement = try portable(String(result[range]))
                result.replaceSubrange(range, with: replacement)
            }
        }
        // Metadata JSON resources use the same vocabulary as the public schema.
        if result.hasPrefix("---\n"), let end = result.range(of: "\n---", range: result.index(result.startIndex, offsetBy: 4)..<result.endIndex) {
            let start = result.index(result.startIndex, offsetBy: 4)
            let header = String(result[start..<end.lowerBound])
            if var object = try JSONSerialization.jsonObject(with: Data(header.utf8)) as? [String: Any] {
                func rewrite(_ value: Any, key: String = "") throws -> Any {
                    if let fields = value as? [String: Any] {
                        var updated: [String: Any] = [:]
                        for (name, child) in fields { updated[name] = try rewrite(child, key: name) }
                        return updated
                    }
                    if let items = value as? [Any] { return try items.map { try rewrite($0, key: key) } }
                    if let reference = value as? String, ["src", "source", "image", "backgroundImage"].contains(key) { return try portable(reference) }
                    return value
                }
                // Do not rewrite user form values or arbitrary user metadata.
                if let layout = object["layout"] { object["layout"] = try rewrite(layout) }
                let encoded = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                result.replaceSubrange(start..<end.lowerBound, with: String(decoding: encoded, as: UTF8.self))
            }
        }
        guard assets.values.reduce(0, { $0 + $1.count }) <= LeonardoZIPArchive.maximumArchiveBytes / 2 else {
            throw LeonardoPackageError.invalidArchive("Resources exceed package size limit")
        }
        return Collection(content: result, assets: assets.sorted(by: { $0.key < $1.key }).map { .init(name: $0.key, data: $0.value) })
    }
}
