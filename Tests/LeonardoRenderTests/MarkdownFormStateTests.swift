import Foundation
import Testing
import LeonardoCore
@testable import LeonardoRender

struct MarkdownFormStateTests {
    @Test func staleUnknownReadOnlyAndWrongTypesAreRejectedAtomically() throws {
        let document = LeonardoDocument(body: "{{field:name}}", metadata: LeonardoMetadata(
            document: LeonardoDocumentDescriptor(kind: .form), fields: [
                "name": LeonardoFieldDefinition(),
                "reference": LeonardoFieldDefinition(readOnly: true),
                "checkbox": LeonardoFieldDefinition(type: .checkbox),
                "hours": LeonardoFieldDefinition(type: .number)
            ]))
        let source = try LeonardoFormatParser.serialize(document)
        let state = MarkdownFormState(baseline: source)
        #expect(state.changes(from: ["source": "stale", "changes": ["name": "other"]], content: source) == nil)
        for invalid: [String: Any] in [
            ["unknown": "x"], ["name": "new", "reference": "tampered"],
            ["checkbox": "true"], ["name": ["nested": "object"]], ["hours": true]
        ] {
            #expect(state.changes(from: ["source": source, "changes": invalid], content: source) == nil)
        }
        let changes = try #require(state.changes(from: ["source": source, "changes": ["name": "漢字", "checkbox": true, "hours": "-"]], content: source))
        #expect(changes["checkbox"] == .boolean(true))
        #expect(changes["hours"] == .string("-"), "Incomplete numeric drafts must remain lossless")
    }

    @Test func formPayloadRequiresExplicitFormatOptInAndCarriesDiagnostics() throws {
        let source = try LeonardoFormatParser.serialize(LeonardoDocument(body: "{{field:email}}", metadata: LeonardoMetadata(
            document: LeonardoDocumentDescriptor(kind: .form),
            fields: ["email": LeonardoFieldDefinition(type: .email, required: true)], values: ["email": .string("invalid")]
        )))
        var config = MarkdownPreviewConfiguration()
        config.allowsLeonardoFormat = true
        config.allowsFormFilling = true
        let payload = try #require(JSONSerialization.jsonObject(with: Data(MarkdownHTMLShell.payloadJSON(content: source, baseURL: nil, configuration: config).utf8)) as? [String: Any])
        #expect(payload["allowsFormFilling"] as? Bool == true)
        #expect((payload["formDiagnostics"] as? [String: [String]])?["email"]?.isEmpty == false)
        let html = try MarkdownHTMLShell.make(content: source, baseURL: nil, configuration: config)
        #expect(html.contains("leonardo-forms.js"))
        #expect(html.contains("leonardo-forms.css"))
        config.allowsLeonardoFormat = false
        let plain = try #require(JSONSerialization.jsonObject(with: Data(MarkdownHTMLShell.payloadJSON(content: "# Plain", baseURL: nil, configuration: config).utf8)) as? [String: Any])
        #expect(plain["leonardo"] == nil)
    }
}
