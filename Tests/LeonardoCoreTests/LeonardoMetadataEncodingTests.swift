import Foundation
import XCTest
@testable import LeonardoCore

final class LeonardoMetadataEncodingTests: XCTestCase {
    func testDefaultDocumentUsesOnlyRequiredEnvelopeKeys() throws {
        let document = LeonardoDocument(body: "# Body\r\n\r\nKeep trailing spaces  \r\n")
        let source = try LeonardoFormatParser.serialize(document)
        let json = try envelope(source)
        XCTAssertEqual(Set(json.keys), ["format", "formatVersion"])
        XCTAssertEqual(json["format"] as? String, "mdlf")
        XCTAssertEqual(json["formatVersion"] as? Int, 1)
        let restored = try LeonardoFormatParser.parse(source)
        XCTAssertEqual(restored.metadata, document.metadata)
        XCTAssertEqual(Array(restored.body.utf8), Array(document.body.utf8))
    }

    func testExplicitEmptyAndOmittedObjectsHaveIdenticalDefaults() throws {
        for descriptor in ["", ", \"document\": {}", ", \"document\": {\"kind\": \"document\"}"] {
            let source = "---\n{\"format\":\"mdlf\",\"formatVersion\":1,\"fields\":{},\"values\":{}\(descriptor)}\n---\nBody"
            let parsed = try LeonardoFormatParser.parse(source)
            XCTAssertEqual(parsed.metadata, LeonardoMetadata())
            let encoded = try LeonardoFormatParser.serialize(parsed)
            XCTAssertEqual(Set(try envelope(encoded).keys), ["format", "formatVersion"])
            XCTAssertEqual(try LeonardoFormatParser.parse(encoded), parsed)
        }
    }

    func testEveryNonDefaultDescriptorIsRetainedIndependently() throws {
        let descriptors: [LeonardoDocumentDescriptor] = [
            .init(id: "article"), .init(title: "Article"), .init(kind: .form),
            .init(revision: 1), .init(locale: "es-ES"),
            .init(id: ""), .init(title: ""), .init(locale: "")
        ]
        for descriptor in descriptors {
            let document = LeonardoDocument(body: "Body", metadata: .init(document: descriptor))
            let source = try LeonardoFormatParser.serialize(document)
            XCTAssertNotNil(try envelope(source)["document"])
            XCTAssertEqual(try LeonardoFormatParser.parse(source), document)
        }
    }

    func testFormDefinitionsAndOpaqueAnswersSurviveCleanup() throws {
        let values: [String: LeonardoJSONValue] = [
            "answer": .null, "enabled": .boolean(false), "text": .string(""),
            "list": .array([]), "object": .object([:]), "zero": .number(0),
            "markdownFrontMatter": .string("---\ntitle: Article\n---\n")
        ]
        let document = LeonardoDocument(body: "Answer: {{field:answer}}", metadata: .init(
            document: .init(kind: .form), fields: ["answer": .init(type: .text)],
            values: values, layout: .init(background: .init(color: "#FFFFFF"))
        ))
        let source = try LeonardoFormatParser.serialize(document)
        XCTAssertEqual(Set(try envelope(source).keys),
                       ["format", "formatVersion", "document", "fields", "values", "layout"])
        XCTAssertEqual(try LeonardoFormatParser.parse(source), document)
    }

    func testOptionalStructuresAreOmittedIndependently() throws {
        let cases: [(LeonardoMetadata, Set<String>)] = [
            (.init(fields: ["name": .init(type: .text)]), ["fields"]),
            (.init(values: ["draft": .null]), ["values"]),
            (.init(layout: .init()), ["layout"])
        ]
        for (metadata, optionalKeys) in cases {
            let document = LeonardoDocument(body: "", metadata: metadata)
            let source = try LeonardoFormatParser.serialize(document)
            XCTAssertEqual(Set(try envelope(source).keys), optionalKeys.union(["format", "formatVersion"]))
            XCTAssertEqual(try LeonardoFormatParser.parse(source), document)
        }
    }

    private func envelope(_ source: String) throws -> [String: Any] {
        let parts = try XCTUnwrap(MarkdownDocumentParser.splitFrontMatter(source))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(parts.metadata.utf8)) as? [String: Any])
    }
}
