import Foundation
import LeonardoCore

/// The baseline is the last source actually sent to the DOM. Native field
/// acknowledgments advance `content` without rebuilding inputs or moving focus.
struct MarkdownFormState {
    var baseline: String?

    func changes(from body: Any, content: String) -> [String: LeonardoJSONValue]? {
        guard let body = body as? [String: Any], let source = body["source"] as? String,
              source == baseline, let values = body["changes"] as? [String: Any],
              JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values),
              let changes = try? JSONDecoder().decode([String: LeonardoJSONValue].self, from: data),
              let document = try? LeonardoFormatParser.parse(content), document.isForm else { return nil }
        for (fieldID, value) in changes {
            guard let field = document.metadata.fields[fieldID], !field.readOnly else { return nil }
            switch (field.type, value) {
            case (.checkbox, .boolean), (.number, .number), (.number, .null): break
            case (.checkbox, _): return nil
            case (_, .string): break
            default: return nil
            }
        }
        return changes
    }
}

public enum MarkdownFormLabels {
    public static let keys = ["Read only", "Required", "Optional", "Help for", "Yes", "No"]
}
