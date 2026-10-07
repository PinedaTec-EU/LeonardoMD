import Foundation

struct MarkdownAppearancePayload: Encodable, Sendable {
    let background: String
    let text: String
    let heading: String
    let accent: String
    let codeBackground: String
    let paperEffect: String
}

extension MarkdownAppearance {
    var sanitizedPayload: MarkdownAppearancePayload {
        MarkdownAppearancePayload(
            background: Self.safeColor(backgroundHex),
            text: Self.safeColor(textHex),
            heading: Self.safeColor(headingHex),
            accent: Self.safeColor(accentHex),
            codeBackground: Self.safeColor(codeBackgroundHex),
            paperEffect: paperEffect.rawValue
        )
    }

    private static func safeColor(_ value: String) -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let isHex = candidate.range(
            of: "^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$",
            options: .regularExpression
        ) != nil
        return isHex ? candidate : "#000000"
    }
}
