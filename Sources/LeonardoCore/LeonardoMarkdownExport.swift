import Foundation

/// Produces a lossy, standalone reading copy; never serializes Leonardo metadata.
public enum LeonardoMarkdownExport {
    public static func markdown(from document: LeonardoDocument) -> String {
        let body = LeonardoLocalImagePolicy.removingNonportableImages(in: document.body)
        let masked = LeonardoLocalImagePolicy.maskCodeAndMetadata(body)
        let tokens = try! NSRegularExpression(pattern: #"\{\{\s*field:([A-Za-z][A-Za-z0-9_.-]{0,63})\s*\}\}"#)
        let result = NSMutableString(string: body)
        for match in tokens.matches(in: masked, range: NSRange(masked.startIndex..., in: masked)).reversed() {
            guard let range = Range(match.range(at: 1), in: body) else { continue }
            let id = String(body[range])
            guard let field = document.metadata.fields[id] else {
                result.replaceCharacters(in: match.range, with: "")
                continue
            }
            let value = document.metadata.values[id] ?? field.defaultValue ?? .null
            result.replaceCharacters(in: match.range, with: literalText(display(value, field: field)))
        }
        return result as String
    }

    private static func display(_ value: LeonardoJSONValue, field: LeonardoFieldDefinition) -> String {
        switch value {
        case .null: return ""
        case let .string(text):
            if field.type == .select {
                return field.options.first(where: { $0.value == text })?.label ?? text
            }
            return text
        case let .boolean(flag): return flag ? "true" : "false"
        case let .number(number): return number.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.significantDigits(1...17)))
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    /// Entity encoding keeps field values literal in prose, headings and GFM tables.
    private static func literalText(_ text: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        return text.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars.map { scalar in
            if scalar == "\n" || scalar == "\r" { return "<br>" }
            if punctuation.contains(scalar) { return "&#\(scalar.value);" }
            return String(scalar)
        }.joined()
    }
}
