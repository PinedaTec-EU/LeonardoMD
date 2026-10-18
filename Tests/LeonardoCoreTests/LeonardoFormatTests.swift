import XCTest
@testable import LeonardoCore

final class LeonardoFormatTests: XCTestCase {
    func testParsesJSONFrontMatterAndKeepsBodySeparate() throws {
        let source = """
        ---
        {
          "format": "mdlf",
          "formatVersion": 1,
          "document": { "kind": "form", "id": "contact", "revision": 3 },
          "fields": {
            "name": { "type": "text", "label": "Name", "required": true, "maxLength": 80 }
          },
          "values": { "name": "Ada" }
        }
        ---
        # Hello {{field:name}}
        """

        let document = try LeonardoFormatParser.parse(source)
        XCTAssertEqual(document.body, "# Hello {{field:name}}")
        XCTAssertEqual(document.metadata.format, "mdlf")
        XCTAssertEqual(document.metadata.formatVersion, 1)
        XCTAssertEqual(document.metadata.document.kind, .form)
        XCTAssertEqual(document.metadata.document.revision, 3)
        XCTAssertEqual(document.metadata.fields["name"]?.type, .text)
        XCTAssertEqual(document.metadata.values["name"]?.stringValue, "Ada")
        XCTAssertEqual(LeonardoFormatParser.detect(source), .leonardo(version: 1))
    }

    func testRoundTripUsesCanonicalSortedJSONAndNormalizesLineEndings() throws {
        let document = LeonardoDocument(
            body: "# Title\r\n\r\nText",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(title: "Title"),
                values: ["count": .number(2)]
            )
        )

        let serialized = try LeonardoFormatParser.serialize(document)
        XCTAssertTrue(serialized.hasPrefix("---\n{"))
        XCTAssertTrue(serialized.contains("\"format\""))
        let restored = try LeonardoFormatParser.parse(serialized)
        XCTAssertEqual(restored.body, "# Title\r\n\r\nText")
        XCTAssertEqual(restored.metadata.document.title, "Title")
        XCTAssertEqual(restored.metadata.values["count"]?.numberValue, 2)
    }

    func testStandardMarkdownDoesNotOptIntoLeonardoParsing() {
        let source = "---\ntitle: Ordinary note\n---\n# Body"
        XCTAssertEqual(LeonardoFormatParser.detect(source), .markdown)
        XCTAssertThrowsError(try LeonardoFormatParser.parse(source)) { error in
            XCTAssertEqual(error as? LeonardoFormatError, .invalidMetadataJSON)
        }
    }

    func testVersionAndFormatFailuresAreExplicit() throws {
        let future = "---\n{\"format\":\"mdlf\",\"formatVersion\":2}\n---\nBody"
        XCTAssertEqual(LeonardoFormatParser.detect(future), .leonardo(version: 2))
        XCTAssertThrowsError(try LeonardoFormatParser.parse(future)) { error in
            XCTAssertEqual(error as? LeonardoFormatError, .unsupportedVersion(2))
        }

        let wrong = "---\n{\"format\":\"other\",\"formatVersion\":1}\n---\nBody"
        XCTAssertEqual(LeonardoFormatParser.detect(wrong), .markdown)
        XCTAssertThrowsError(try LeonardoFormatParser.parse(wrong)) { error in
            XCTAssertEqual(error as? LeonardoFormatError, .missingFormatIdentifier)
        }
    }

    func testModeHintsAreExtensionOnly() {
        XCTAssertEqual(LeonardoFormatParser.modeHint(forPathExtension: "mdlf"), .edit)
        XCTAssertEqual(LeonardoFormatParser.modeHint(forPathExtension: "MDLR"), .fill)
        XCTAssertNil(LeonardoFormatParser.modeHint(forPathExtension: "md"))
        XCTAssertNil(LeonardoFormatParser.modeHint(forPathExtension: "mdlz"))
    }

    func testDraftAllowsIncompleteRequiredFormButSubmissionRejectsIt() throws {
        let document = LeonardoDocument(
            body: "Name: {{field:name}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(kind: .form),
                fields: ["name": LeonardoFieldDefinition(type: .text, required: true)]
            )
        )

        let draft = LeonardoFormatValidator.validate(document, context: .draft)
        XCTAssertTrue(draft.contains { $0.code == "field.required" && $0.severity == .warning })
        XCTAssertTrue(LeonardoFormatValidator.isValid(document, context: .draft))
        let submission = LeonardoFormatValidator.validate(document, context: .submission)
        XCTAssertTrue(submission.contains { $0.code == "field.required" && $0.severity == .error })
        XCTAssertFalse(LeonardoFormatValidator.isValid(document, context: .submission))
    }

    func testFieldTypesAndConstraintsProduceActionableDiagnostics() {
        let document = LeonardoDocument(
            body: "{{field:email}} {{field:choice}} {{field:done}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(kind: .form),
                fields: [
                    "email": LeonardoFieldDefinition(type: .email, required: true, pattern: "^.+@example\\.com$"),
                    "choice": LeonardoFieldDefinition(type: .select, options: [LeonardoFieldOption(value: "a")]),
                    "done": LeonardoFieldDefinition(type: .checkbox)
                ],
                values: [
                    "email": .string("invalid"),
                    "choice": .string("b"),
                    "done": .string("yes")
                ]
            )
        )

        let diagnostics = LeonardoFormatValidator.validate(document)
        XCTAssertTrue(diagnostics.contains { $0.code == "value.pattern" && $0.fieldID == "email" })
        XCTAssertTrue(diagnostics.contains { $0.code == "value.option" && $0.fieldID == "choice" })
        XCTAssertTrue(diagnostics.contains { $0.code == "value.type" && $0.fieldID == "done" })
    }

    func testUnknownBodyFieldAndUnsafeAssetAreRejected() {
        let document = LeonardoDocument(
            body: "{{field:missing}}",
            metadata: LeonardoMetadata(
                fields: ["known": LeonardoFieldDefinition()],
                layout: LeonardoLayout(
                    background: LeonardoBackground(image: "../background.png"),
                    images: [LeonardoImageLayout(source: "javascript:alert(1)")]
                )
            )
        )
        let diagnostics = LeonardoFormatValidator.validate(document)
        XCTAssertTrue(diagnostics.contains { $0.code == "body.unknownField" })
        XCTAssertTrue(diagnostics.contains { $0.code == "layout.backgroundImage" })
        XCTAssertTrue(diagnostics.contains { $0.code == "layout.imageSource" })
    }

    func testLayoutSupportsPercentAndAbsolutePlacement() {
        let layout = LeonardoLayout(
            background: LeonardoBackground(
                image: "assets/background.png",
                opacity: 0.4,
                position: LeonardoPosition(placement: .absolute, x: LeonardoDimension(value: 50, unit: .percent), y: LeonardoDimension(value: 50, unit: .percent))
            ),
            images: [LeonardoImageLayout(
                source: "assets/logo.svg",
                size: LeonardoSize(width: LeonardoDimension(value: 180, unit: .points)),
                position: LeonardoPosition(placement: .relative, x: LeonardoDimension(value: -4, unit: .percent))
            )],
            tables: [LeonardoTableLayout(
                occurrence: 1,
                columns: [
                    LeonardoTableColumnLayout(width: LeonardoDimension(value: 35, unit: .percent)),
                    LeonardoTableColumnLayout(width: LeonardoDimension(value: 240, unit: .points))
                ]
            )]
        )
        let document = LeonardoDocument(body: "| A | B |\n|---|---|\n| 1 | 2 |", metadata: LeonardoMetadata(layout: layout))
        XCTAssertTrue(LeonardoFormatValidator.isValid(document))
    }
}
