import XCTest
@testable import LeonardoCore

final class LeonardoGraphicTests: XCTestCase {
    private var rubric: LeonardoRubric {
        .init(strokes: [.init(color: "#102030", width: 4, style: .brush, points: [.init(x: 10, y: 20), .init(x: 50, y: 60), .init(x: 90, y: 20)])])
    }
    func testRoundTripRetainsDefinitionOrderGeometryAndEditableStrokes() throws {
        let first = LeonardoGraphic(id: "first", label: "First", rubric: rubric, page: 2, x: -12, y: 120, z: -1)
        let second = LeonardoGraphic(id: "second", label: "Second", rubric: rubric, page: 1, z: -1)
        let document = LeonardoDocument(body: "First\n\n<!-- leonardo:page-break -->\n\nSecond", metadata: .init(layout: .init(objects: [first, second])))
        let copy = try LeonardoFormatParser.parse(LeonardoFormatParser.serialize(document))
        XCTAssertEqual(copy, document)
        XCTAssertEqual(copy.metadata.layout?.objects.map(\.id), ["first", "second"])
        XCTAssertLessThan(rubric.strokes[0].segmentWidth(at: 0), rubric.strokes[0].segmentWidth(at: 1))
        XCTAssertLessThan(rubric.strokes[0].segmentWidth(at: 2), rubric.strokes[0].segmentWidth(at: 1))
    }
    func testRejectsUnsafeSourcesAmbiguousObjectsAndDuplicateIDs() throws {
        let valid = LeonardoGraphic(id: "one", label: "Ink", rubric: rubric)
        var invalid = valid; invalid.source = "assets/image.png"
        var duplicate = valid; duplicate.label = "Other"
        for objects in [[invalid], [valid, duplicate]] {
            XCTAssertThrowsError(try LeonardoFormatParser.serialize(.init(body: "", metadata: .init(layout: .init(objects: objects)))))
        }
        for source in ["../secret.png", "file:///tmp/image.png", "javascript:alert(1)"] {
            let image = LeonardoGraphic(label: "Unsafe", source: source)
            XCTAssertThrowsError(try LeonardoFormatParser.serialize(.init(body: "", metadata: .init(layout: .init(objects: [image])))))
        }
    }
    func testRubricFieldsOnlyAcceptValidatedInkAndNeverChangeStructure() throws {
        let field = LeonardoFieldDefinition(type: .rubric, rubricSize: .init(width: 200, height: 80), required: true)
        let document = LeonardoDocument(body: "{{field:signature}}", metadata: .init(fields: ["signature": field]))
        let filled = try XCTUnwrap(document.applyingFormValues(["signature": try XCTUnwrap(rubric.jsonValue)]))
        XCTAssertEqual(filled.body, document.body)
        XCTAssertEqual(filled.metadata.fields, document.metadata.fields)
        XCTAssertEqual(try LeonardoFormatParser.parse(LeonardoFormatParser.serialize(filled)), filled)
        XCTAssertFalse(LeonardoFormatValidator.validate(filled, context: .submission).contains { $0.severity == .error })
        XCTAssertNil(document.applyingFormValues(["signature": .string("not ink")]))
        var locked = document; locked.metadata.fields["signature"]?.readOnly = true
        XCTAssertNil(locked.applyingFormValues(["signature": try XCTUnwrap(rubric.jsonValue)]))
    }
    func testInkBudgetAndMalformedGeometryAreRejected() throws {
        var invalid = rubric; invalid.strokes[0].points[0].x = .infinity
        XCTAssertFalse(invalid.isValid)
        invalid = rubric; invalid.strokes[0].color = "red; background:url(x)"
        XCTAssertFalse(invalid.isValid)
        invalid = rubric; invalid.strokes[0].points = Array(repeating: .init(x: 1, y: 1), count: 20001)
        XCTAssertFalse(invalid.isValid)
        var object = LeonardoGraphic(label: "Invalid", rubric: rubric); object.page = 0
        XCTAssertThrowsError(try LeonardoFormatParser.serialize(.init(body: "", metadata: .init(layout: .init(objects: [object])))))
    }
}
