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

final class LeonardoMarkdownLiteralFields: @unchecked Sendable {
    static let shared = LeonardoMarkdownLiteralFields()

    // JavaScriptCore objects stay behind one lock. Markdown is passed as data
    // to the bundled parser and never evaluated as JavaScript.
    private let lock = NSLock()
    private let context: JSContext?

    private init() {
        guard let url = LeonardoMarkdownParserResource.scriptURL,
              let marked = try? String(contentsOf: url, encoding: .utf8),
              let parser = JSContext() else {
            context = nil
            return
        }
        parser.evaluateScript(marked)
        parser.evaluateScript(#"""
        function leonardoCodeFieldOrdinals(markdown, prefix) {
          const fields = [];
          const tokens = marked.lexer(markdown, { gfm: true, breaks: false });
          const placeholder = new RegExp("\\{\\{\\s*field:" + prefix + "([0-9]+)\\s*\\}\\}", "g");
          marked.walkTokens(tokens, token => {
            if (token.type !== "code" && token.type !== "codespan") return;
            for (const match of token.text.matchAll(placeholder)) fields.push(Number(match[1]));
          });
          return fields;
        }
        """#)
        context = parser.exception == nil ? parser : nil
    }

    func ordinals(in body: String, fieldRanges: [NSRange]) throws -> Set<Int> {
        guard !fieldRanges.isEmpty else { return [] }
        let prefix = "Leonardo" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let probe = NSMutableString(string: body)
        for (ordinal, range) in fieldRanges.enumerated().reversed() {
            probe.replaceCharacters(in: range, with: "\(prefix)\(ordinal)")
        }

        lock.lock()
        defer { lock.unlock() }
        guard let context else { throw LeonardoSigningError.storageFailure }
        context.exception = nil
        guard let function = context.objectForKeyedSubscript("leonardoCodeFieldOrdinals"),
              let result = function.call(withArguments: [probe as String, prefix]),
              context.exception == nil,
              let ordinals = result.toArray() as? [Int] else {
            throw LeonardoSigningError.storageFailure
        }
        return Set(ordinals)
    }
}
