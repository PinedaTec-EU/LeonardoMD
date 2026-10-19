import CryptoKit
import Foundation

/// Rewrites only resource references in the exported copy. Originals are never modified.
public enum LeonardoLocalImagePolicy {
    public static let extensions: Set<String> = ["bmp", "gif", "ico", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]

    /// Returns whether a document refers to one or more local image resources.
    ///
    /// The check is deliberately independent of the file system. It only
    /// inspects the canonical document representation and considers relative
    /// paths and `file:` URLs with a supported image extension local. This is
    /// the same scanner used by package export, so an application can choose a
    /// portable response before it starts an I/O operation.
    ///
    /// - Throws: If the document cannot be serialized as a valid MDLF value.
    public static func hasLocalResources(in document: LeonardoDocument) throws -> Bool {
        let canonical = try LeonardoFormatParser.serialize(document)
        if bodyReferences(in: canonical).contains(where: { isLocalReference($0.value) }) {
            return true
        }
        return metadataReferences(in: document.metadata).contains(where: { isLocalReference($0) })
    }

    fileprivate struct BodyReference {
        let range: NSRange
        let value: String
    }

    /// Scans only Markdown/HTML body content. Metadata is masked so arbitrary
    /// form values cannot be interpreted as image references.
    fileprivate static func bodyReferences(in source: String) -> [BodyReference] {
        let masked = maskCodeAndMetadata(source)
        var references: [BodyReference] = []

        let inlineExpressions = [
            #"!\[[^\]\n]*\]\(\s*<([^>\n]+)>(?:\s+["'][^\n]*?["'])?\s*\)"#,
            #"!\[[^\]\n]*\]\(\s*([^<\s)]+)(?:\s+["'][^\n]*?["'])?\s*\)"#,
            #"(?i)<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#
        ]
        for expression in inlineExpressions {
            guard let regex = try? NSRegularExpression(pattern: expression) else { continue }
            let matches = regex.matches(in: masked, range: NSRange(masked.startIndex..., in: masked))
            for match in matches {
                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: source) else { continue }
                references.append(BodyReference(range: match.range(at: 1), value: String(source[valueRange])))
            }
        }

        // A reference image points at the destination in its definition. The
        // destination is the only text that must be rewritten; the image use
        // itself remains exactly `![alt][label]` (or its collapsed/shortcut
        // form). The first definition wins, matching Markdown's semantics.
        let definitions = referenceDefinitions(in: source, masked: masked)
        if let usageRegex = try? NSRegularExpression(
            pattern: #"!\[([^\]\n]*)\](?:\[([^\]\n]*)\])?(?!\s*\()"#
        ) {
            var seenRanges = Set<String>()
            let usages = usageRegex.matches(in: masked, range: NSRange(masked.startIndex..., in: masked))
            for usage in usages {
                guard let label = referenceLabel(for: usage, in: masked),
                      let definition = definitions[normalizeReferenceLabel(label)] else { continue }
                let key = "\(definition.range.location):\(definition.range.length)"
                guard seenRanges.insert(key).inserted else { continue }
                references.append(definition)
            }
        }

        return references.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location { return lhs.range.length < rhs.range.length }
            return lhs.range.location < rhs.range.location
        }
    }

    fileprivate static func isLocalReference(_ reference: String) -> Bool {
        guard !reference.isEmpty, !reference.hasPrefix("#") else { return false }
        let parsed = URL(string: reference)
        if let scheme = parsed?.scheme?.lowercased(), scheme != "file" { return false }
        let path: String
        if let fileURL = parsed, fileURL.scheme?.lowercased() == "file" {
            path = fileURL.path
        } else {
            let decoded = reference.removingPercentEncoding ?? reference
            if let parsedPath = parsed?.path, !parsedPath.isEmpty { path = parsedPath }
            else { path = decoded }
        }
        return extensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private static func metadataReferences(in metadata: LeonardoMetadata) -> [String] {
        guard let layout = metadata.layout else { return [] }
        var references = layout.images.map(\.source)
        if let image = layout.background?.image { references.append(image) }
        return references
    }

    private static func normalizeReferenceLabel(_ label: String) -> String {
        label.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    private static func referenceDefinitions(in source: String, masked: String) -> [String: BodyReference] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?im)^ {0,3}\[([^\]\n]+)\]:[ \t]*(?:<([^>\n]+)>|([^\s]+))(?:[ \t]+(?:["'][^\n]*?["']|\([^\n]*?\)))?[ \t]*(?:\n|$)"#
        ) else { return [:] }
        var definitions: [String: BodyReference] = [:]
        let matches = regex.matches(in: masked, range: NSRange(masked.startIndex..., in: masked))
        for match in matches {
            guard let labelRange = Range(match.range(at: 1), in: masked),
                  !labelRange.isEmpty else { continue }
            let label = String(masked[labelRange])
            let destinationIndex: Int
            if match.range(at: 2).location != NSNotFound { destinationIndex = 2 }
            else if match.range(at: 3).location != NSNotFound { destinationIndex = 3 }
            else { continue }
            guard let valueRange = Range(match.range(at: destinationIndex), in: source) else { continue }
            let key = normalizeReferenceLabel(label)
            guard definitions[key] == nil else { continue }
            definitions[key] = BodyReference(
                range: match.range(at: destinationIndex),
                value: String(source[valueRange])
            )
        }
        return definitions
    }

    private static func referenceLabel(for match: NSTextCheckingResult, in masked: String) -> String? {
        let explicit = match.range(at: 2)
        if explicit.location != NSNotFound, explicit.length > 0,
           let range = Range(explicit, in: masked) {
            return String(masked[range])
        }
        let collapsed = match.range(at: 1)
        guard let range = Range(collapsed, in: masked) else { return nil }
        return String(masked[range])
    }

    private static func maskCodeAndMetadata(_ source: String) -> String {
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
            if let scheme = URL(string: reference)?.scheme?.lowercased(), scheme != "file" { return reference }
            if let existing = mapping[reference] { return existing }
            let decoded = reference.removingPercentEncoding ?? reference
            let url: URL
            if let fileURL = URL(string: reference), fileURL.scheme?.lowercased() == "file" { url = fileURL }
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
        // The same body scanner is used by the application-side package
        // decision, keeping inline, HTML and reference images in sync.
        var result = try LeonardoFormatParser.serialize(LeonardoFormatParser.parse(content))
        for reference in LeonardoLocalImagePolicy.bodyReferences(in: result).reversed() {
            guard let range = Range(reference.range, in: result) else { continue }
            let replacement = try portable(String(result[range]))
            result.replaceSubrange(range, with: replacement)
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
