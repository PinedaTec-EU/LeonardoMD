import Foundation
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

    func testReservationPersistsAndFinishIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("form.mdlf")
        let store = LeonardoFormReservationStore(root: root)
        let owner = LeonardoFormReservationStore.Reservation(id: UUID(), deviceID: UUID(), revision: "v1")
        let other = LeonardoFormReservationStore.Reservation(id: UUID(), deviceID: UUID(), revision: "v1")
        try store.acquire(owner, for: source) { "v1" }

        let reopened = LeonardoFormReservationStore(root: root)
        XCTAssertEqual(try reopened.activeReservation(for: source), owner)
        XCTAssertThrowsError(try reopened.acquire(other, for: source) { "v1" })
        XCTAssertThrowsError(try reopened.withEditingAccess(to: source) { XCTFail("Editor was admitted") })

        let values: [String: LeonardoJSONValue] = ["name": .string("Ana")]
        XCTAssertThrowsError(try reopened.finish(owner, for: source, values: values) { ("v2", template) })
        XCTAssertEqual(try reopened.activeReservation(for: source), owner)
        let response = try reopened.finish(owner, for: source, values: values) { ("v1", template) }
        XCTAssertNil(try store.activeReservation(for: source))
        XCTAssertEqual(try store.finish(owner, for: source, values: values) {
            throw LeonardoFormReservationStore.Failure.revisionChanged
        }, response)
        XCTAssertThrowsError(try store.finish(owner, for: source, values: ["name": .string("Eva")]) {
            ("v1", template)
        })
        try store.acquire(other, for: source) { "v1" }
        try store.cancel(other, for: source)
        XCTAssertNil(try store.activeReservation(for: source))
        XCTAssertThrowsError(try store.acquire(other, for: source) { "v1" })
    }
}
