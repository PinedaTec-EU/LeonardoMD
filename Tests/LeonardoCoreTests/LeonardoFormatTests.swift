import Foundation
import XCTest
@testable import LeonardoCore

final class LeonardoFormatTests: XCTestCase {
    func testFormatCorpusParsesRoundTripsAndHasNoSemanticErrors() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let examples = repository.appendingPathComponent("doc/format/examples", isDirectory: true)
        for name in ["request.mdlf", "request.mdlr"] {
            let url = examples.appendingPathComponent(name)
            let source = try String(contentsOf: url, encoding: .utf8)
            let document = try LeonardoFormatParser.parse(source)
            let errors = LeonardoFormatValidator.validate(document).filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "\(name) has errors: \(errors)")
            let restored = try LeonardoFormatParser.parse(try LeonardoFormatParser.serialize(document))
            XCTAssertEqual(restored.body, document.body, name)
            XCTAssertEqual(restored.metadata, document.metadata, name)
        }
    }

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

    func testBodyPreservesLeadingTrailingWhitespaceAndCRLF() throws {
        let source = "---\r\n{\"format\":\"mdlf\",\"formatVersion\":1}\r\n---\r\n\r\n# Body  \r\n"
        let document = try LeonardoFormatParser.parse(source)
        XCTAssertEqual(document.body, "\r\n# Body  \r\n")
        XCTAssertEqual(try LeonardoFormatParser.parse(try LeonardoFormatParser.serialize(document)).body, document.body)
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

    func testRejectsDuplicateRootMetadataKeysBeforeDictionaryConversion() {
        let source = "---\n{\"format\":\"mdlf\",\"formatVersion\":1,\"format\":\"mdlf\"}\n---\nBody"
        XCTAssertThrowsError(try LeonardoFormatParser.parse(source)) { error in
            XCTAssertEqual(error as? LeonardoFormatError, .invalidMetadataJSON)
        }
        XCTAssertEqual(LeonardoFormatParser.detect(source), .malformedLeonardo)
    }

    func testRejectsDuplicateKeysInsideFieldDefinitions() {
        let source = "---\n{\"format\":\"mdlf\",\"formatVersion\":1,\"fields\":{\"name\":{\"type\":\"text\",\"type\":\"email\"}}}\n---\nBody"
        XCTAssertThrowsError(try LeonardoFormatParser.parse(source)) { error in
            XCTAssertEqual(error as? LeonardoFormatError, .invalidMetadataJSON)
        }
    }

    func testRejectsDuplicateKeysInsideNestedOpaqueValues() {
        let source = "---\n{\"format\":\"mdlf\",\"formatVersion\":1,\"values\":{\"payload\":{\"items\":[{\"name\":1,\"name\":2}]}}}\n---\nBody"
        XCTAssertThrowsError(try LeonardoFormatParser.parse(source)) { error in
            XCTAssertEqual(error as? LeonardoFormatError, .invalidMetadataJSON)
        }
    }

    func testRejectsEscapedSpellingsOfDuplicateKeys() {
        let source = "---\n{\"format\":\"mdlf\",\"formatVersion\":1,\"values\":{\"\\u0070ayload\":1,\"payload\":2}}\n---\nBody"
        XCTAssertThrowsError(try LeonardoFormatParser.parse(source)) { error in
            XCTAssertEqual(error as? LeonardoFormatError, .invalidMetadataJSON)
        }
    }

    func testRejectsIncompleteOrTrailingMetadataBeforeDictionaryConversion() {
        for metadata in [
            "{\"format\":\"mdlf\",\"formatVersion\":1,}",
            "{\"format\":\"mdlf\",\"formatVersion\":1} true",
            "\u{FEFF}{\"format\":\"mdlf\",\"formatVersion\":1,\"values\":{\"a\":1,\"a\":2}}"
        ] {
            XCTAssertThrowsError(try LeonardoFormatParser.parse("---\n" + metadata + "\n---\nBody")) {
                XCTAssertEqual($0 as? LeonardoFormatError, .invalidMetadataJSON)
            }
        }
    }

    func testAllowsRepeatedKeysInSeparateObjects() throws {
        let source = """
        ---
        {
          "format": "mdlf",
          "formatVersion": 1,
          "fields": {
            "first": { "type": "text", "label": "First" },
            "second": { "type": "text", "label": "Second" }
          },
          "values": {
            "first": { "label": "one" },
            "second": { "label": "two" }
          }
        }
        ---
        Body
        """
        let document = try LeonardoFormatParser.parse(source)
        XCTAssertEqual(document.metadata.fields.count, 2)
        XCTAssertEqual(document.metadata.values.count, 2)
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

    func testUnknownStructuralMetadataIsRejectedInsteadOfDiscarded() {
        let source = "---\n{\"format\":\"mdlf\",\"formatVersion\":1,\"layout\":{\"background\":{\"tint\":\"blue\"}}}\n---\nBody"
        XCTAssertThrowsError(try LeonardoFormatParser.parse(source)) { error in
            XCTAssertEqual(error as? LeonardoFormatError, .unknownMetadataKey("layout.background.tint"))
        }
    }

    func testPartialLayoutObjectsUseDocumentedDefaults() throws {
        let source = "---\n{\"format\":\"mdlf\",\"formatVersion\":1,\"layout\":{\"background\":{\"position\":{}},\"tables\":[{\"occurrence\":1,\"width\":{\"value\":100,\"unit\":\"percent\"},\"columns\":[{}]}]}}\n---\nBody"
        let document = try LeonardoFormatParser.parse(source)
        let background = try XCTUnwrap(document.metadata.layout?.background)
        XCTAssertEqual(background.opacity, 1)
        XCTAssertEqual(background.fit, .cover)
        XCTAssertEqual(background.position.placement, .flow)
        let table = try XCTUnwrap(document.metadata.layout?.tables.first)
        XCTAssertEqual(table.occurrence, 1)
        XCTAssertEqual(table.repeatHeader, true)
        XCTAssertEqual(table.allowRowBreak, true)
        XCTAssertEqual(table.columns.count, 1)
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

    func testExpensiveUngroupedPatternHasABoundedExecutionBudget() {
        let clock = ContinuousClock()
        let start = clock.now
        let document = LeonardoDocument(body: "{{field:code}}", metadata: LeonardoMetadata(
            fields: ["code": LeonardoFieldDefinition(pattern: "^a+a+a+a+a+a+a+a+$")],
            values: ["code": .string(String(repeating: "a", count: 5_000) + "!")]))
        let diagnostics = LeonardoFormatValidator.validate(document)
        XCTAssertTrue(diagnostics.contains { $0.code == "value.pattern" })
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(2))
    }

    func testDateValidationUsesGregorianCalendarAndCustomMessage() {
        let document = LeonardoDocument(
            body: "{{field:date}} {{field:unsafe}}",
            metadata: LeonardoMetadata(
                fields: [
                    "date": LeonardoFieldDefinition(type: .date),
                    "unsafe": LeonardoFieldDefinition(
                        type: .text,
                        pattern: "(a|aa)+$",
                        validationMessage: "Use a simple identifier."
                    )
                ],
                values: [
                    "date": .string("2023-02-29"),
                    "unsafe": .string("bbb")
                ]
            )
        )

        var diagnostics = LeonardoFormatValidator.validate(document)
        XCTAssertTrue(diagnostics.contains { $0.code == "value.date" && $0.fieldID == "date" })
        XCTAssertTrue(diagnostics.contains { $0.code == "field.patternSafety" && $0.fieldID == "unsafe" })
        XCTAssertFalse(diagnostics.contains { $0.code == "value.pattern" && $0.fieldID == "unsafe" })

        var leapYear = document
        leapYear.metadata.values["date"] = .string("2024-02-29")
        diagnostics = LeonardoFormatValidator.validate(leapYear)
        XCTAssertFalse(diagnostics.contains { $0.code == "value.date" && $0.fieldID == "date" })

        var custom = document
        custom.metadata.values["unsafe"] = .string("abc")
        custom.metadata.fields["unsafe"]?.pattern = "^a+$"
        diagnostics = LeonardoFormatValidator.validate(custom)
        XCTAssertTrue(diagnostics.contains { $0.code == "value.pattern" && $0.message == "Use a simple identifier." })
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
