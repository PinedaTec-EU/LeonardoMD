import Foundation
import JavaScriptCore

/// The preview and guided-signing engine use the same bundled Markdown parser.
public enum LeonardoMarkdownParserResource {
    public static var scriptURL: URL? {
        Bundle.module.url(forResource: "marked.umd", withExtension: "js")
    }

    public static var licenseURL: URL? {
        Bundle.module.url(forResource: "marked-15.0.7", withExtension: "txt")
    }
}

final class LeonardoSigningMarkdown: @unchecked Sendable {
    static let shared = LeonardoSigningMarkdown()

    // JavaScriptCore objects stay behind one lock. Markdown is passed as data
    // to the bundled parser and never evaluated as JavaScript.
    private let lock = NSLock()
    private let context: JSContext?

    private init() {
        guard let url = LeonardoMarkdownParserResource.scriptURL,
              let marked = try? String(contentsOf: url, encoding: .utf8),
              let entitiesURL = Bundle.module.url(forResource: "whatwg-html-entities", withExtension: "json"),
              let entities = try? String(contentsOf: entitiesURL, encoding: .utf8),
              let locationsURL = Bundle.module.url(forResource: "leonardo-signing-locations", withExtension: "js"),
              let locations = try? String(contentsOf: locationsURL, encoding: .utf8),
              let parser = JSContext() else {
            context = nil
            return
        }
        parser.evaluateScript(marked)
        parser.evaluateScript("const leonardoSigningHTMLEntities = Object.freeze(\(entities));")
        parser.evaluateScript(locations)
        context = parser.exception == nil ? parser : nil
    }

    func visibleOrdinals(in body: String, fieldRanges: [NSRange], fieldIDs: Set<String>) throws -> Set<Int> {
        let prefix = "Leonardo" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let original = body as NSString
        let ids = fieldRanges.map { original.substring(with: $0) }
        let probe = NSMutableString(string: body)
        for (ordinal, range) in fieldRanges.enumerated().reversed() {
            probe.replaceCharacters(in: range, with: "\(prefix)\(ordinal)")
        }

        return try evaluate("leonardoVisibleRubrics", arguments: [
            body, ["text": probe as String, "ids": ids], Array(fieldIDs), prefix
        ]) { result in
            guard !result.isNull, let ordinals = result.toArray() as? [Int] else {
                throw LeonardoSigningError.unmappedSigningLocation
            }
            return Set(ordinals)
        }
    }

    func imageReferences(in body: String) throws -> [String] {
        guard body.contains("!") || body.contains("<") else { return [] }
        return try evaluate("leonardoSigningImageReferences", arguments: [body]) { result in
            guard let references = result.toArray() as? [String] else {
                throw LeonardoSigningError.storageFailure
            }
            return references
        }
    }

    private func evaluate<T>(
        _ name: String,
        arguments: [Any],
        decode: (JSValue) throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let context else { throw LeonardoSigningError.storageFailure }
        context.exception = nil
        guard let function = context.objectForKeyedSubscript(name),
              let result = function.call(withArguments: arguments),
              context.exception == nil else {
            throw LeonardoSigningError.storageFailure
        }
        return try decode(result)
    }
}
