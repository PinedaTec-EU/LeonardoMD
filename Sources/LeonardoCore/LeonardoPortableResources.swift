import CryptoKit
import Foundation

/// Rewrites only resource references in the exported copy. Originals are never modified.
public enum LeonardoLocalImagePolicy {
    public static let extensions: Set<String> = ["bmp", "gif", "ico", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
}

enum LeonardoPortableResources {
    struct Collection {
        var content: String
        var assets: [LeonardoZIPArchive.Entry]
    }

    static func collect(content: String, documentURL: URL, assetRoot: URL? = nil) throws -> Collection {
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
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let roots = [base, assetRoot].compactMap { $0?.resolvingSymlinksInPath().path }
            guard LeonardoLocalImagePolicy.extensions.contains(resolved.pathExtension.lowercased()),
                  roots.contains(where: { resolved.path.hasPrefix($0 + "/") }) else {
                throw LeonardoPackageError.missingAsset(reference)
            }
            let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let size = values?.fileSize,
                  size <= LeonardoZIPArchive.maximumArchiveBytes / 2 else { throw LeonardoPackageError.missingAsset(reference) }
            let bytes = try Data(contentsOf: resolved)
            let hash = SHA256.hash(data: bytes).prefix(8).map { String(format: "%02x", $0) }.joined()
            let suffix = url.pathExtension.lowercased().filter { $0.isASCII && $0.isLetter || $0.isNumber }
            let name = "assets/\(hash)\(suffix.isEmpty ? "" : "." + suffix)"
            assets[name] = bytes
            mapping[reference] = name
            return name
        }
        // Markdown inline images (including angle-bracket destinations) and reference definitions.
        var result = try LeonardoFormatParser.serialize(LeonardoFormatParser.parse(content))
        let expressions = [
            #"!\[[^\]\n]*\]\(\s*<([^>\n]+)>(?:\s+["'][^\n]*?["'])?\s*\)"#,
            #"!\[[^\]\n]*\]\(\s*([^<\s)]+)(?:\s+["'][^\n]*?["'])?\s*\)"#,
            #"(?i)<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#
        ]
        for expression in expressions {
            let regex = try NSRegularExpression(pattern: expression)
            let masked = maskCode(result)
            let matches = regex.matches(in: masked, range: NSRange(masked.startIndex..., in: masked))
            for match in matches.reversed() {
                guard let range = Range(match.range(at: 1), in: result) else { continue }
                let replacement = try portable(String(result[range]))
                result.replaceSubrange(range, with: replacement)
            }
        }
        // Resolve reference-style images only; ordinary document hyperlinks remain links.
        let masked = maskCode(result)
        let labels = try NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\[([^\]\n]*)\]"#)
        let references = labels.matches(in: masked, range: NSRange(masked.startIndex..., in: masked)).compactMap { match -> String? in
            let range = match.range(at: match.range(at: 2).length == 0 ? 1 : 2)
            return Range(range, in: masked).map { String(masked[$0]).lowercased() }
        }
        for label in Set(references) {
            let definition = try NSRegularExpression(pattern: #"(?im)^ {0,3}\["# + NSRegularExpression.escapedPattern(for: label) + #"\]:[ \t]*<?([^\s>]+)>?"#)
            let currentMask = maskCode(result)
            for match in definition.matches(in: currentMask, range: NSRange(currentMask.startIndex..., in: currentMask)).reversed() {
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

    private static func maskCode(_ source: String) -> String {
        // Replace by UTF-16 units so NSRegularExpression ranges retain their offsets.
        let patterns = [#"(?ms)^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1[^\n]*(?:\n|$)"#, #"`+[^`\n]*`+"#]
        let masked = NSMutableString(string: source)
        if source.hasPrefix("---\n"), let closing = source.range(of: "\n---", range: source.index(source.startIndex, offsetBy: 4)..<source.endIndex) {
            let range = NSRange(source.startIndex..<closing.upperBound, in: source)
            masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: masked as String, range: NSRange(location: 0, length: masked.length)).reversed() {
                masked.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
            }
        }
        return masked as String
    }
}
