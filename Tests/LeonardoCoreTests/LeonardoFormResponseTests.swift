import XCTest
@testable import LeonardoCore

final class LeonardoFormResponseTests: XCTestCase {
    private let template = LeonardoDocument(
        body: "{{field:name}}\n\n{{field:reference}}\n",
        metadata: LeonardoMetadata(
            document: LeonardoDocumentDescriptor(kind: .form),
            fields: [
                "name": LeonardoFieldDefinition(type: .text, required: true),
                "reference": LeonardoFieldDefinition(type: .text, readOnly: true)
            ],
            values: ["reference": .string("123")]
        )
    )

    func testResponseUsesTemplateStructureAndPreservesExistingValues() throws {
        let response = try template.makeFormResponse(applying: ["name": .string("Ana")])
        XCTAssertEqual(response.body, template.body)
        XCTAssertEqual(response.metadata.fields, template.metadata.fields)
        XCTAssertEqual(response.metadata.values, ["name": .string("Ana"), "reference": .string("123")])
        XCTAssertEqual(template.metadata.values, ["reference": .string("123")])
    }

    func testResponseRejectsWritesOutsideEditableFields() {
        for field in ["reference", "unknown"] {
            XCTAssertThrowsError(try template.makeFormResponse(applying: [field: .string("Ana")])) { error in
                guard case LeonardoFormResponseError.rejectedValues = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testResponseRequiresMandatoryAnswers() {
        XCTAssertThrowsError(try template.makeFormResponse(applying: [:])) { error in
            guard case LeonardoFormResponseError.invalidResponse(let diagnostics) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(diagnostics.contains { $0.code == "field.required" && $0.fieldID == "name" })
        }
    }
}
