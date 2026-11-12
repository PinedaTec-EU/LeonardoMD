import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class GraphicInspectionTests: XCTestCase {
    func testRecolorPreservesGeometryOtherObjectsLibraryAndHistoryThroughSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ink = LeonardoRubric(strokes: [
            .init(color: "#112233", width: 3, style: .solid, points: [.init(x: 10, y: 20), .init(x: 80, y: 100)]),
            .init(color: "#AA3344", width: 6, style: .brush, points: [.init(x: 90, y: 30), .init(x: 100, y: 40)])])
        let first = LeonardoGraphic(label: "First", rubric: ink, x: 45, y: 90, width: 180, height: 60, z: -2)
        let other = LeonardoGraphic(label: "Other", rubric: ink)
        let doc = LeonardoDocument(body: "# Unchanged body\n\nInspection prose.", metadata: .init(layout: .init(objects: [first, other])))
        let url = root.appendingPathComponent("test.mdlf")
        try LeonardoFormatParser.serialize(doc).write(to: url, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("prefs.json"))
        session.authorizePath = { _, _ in }; defer { session.stop() }
        session.rubricLibrary = RubricLibrary(url: root.appendingPathComponent("rubrics.json"))
        try session.rubricLibrary.add(label: "Original", rubric: ink)
        await session.openDocument(url); session.isProtected = false
        session.receiveGraphicSelection(expected: "stale", id: first.id, inspect: true)
        XCTAssertNil(session.selectedGraphic)
        session.receiveGraphicSelection(expected: session.content, id: first.id, inspect: true)
        XCTAssertTrue(session.showsGraphicInspector)
        XCTAssertTrue(session.recolorInspectedGraphic(first, color: "#55AAEE"))
        let updated = try XCTUnwrap(session.selectedGraphic)
        var expected = first
        expected.rubric?.strokes[0].color = "#55AAEE"; expected.rubric?.strokes[1].color = "#55AAEE"
        XCTAssertEqual(updated, expected)
        XCTAssertEqual(session.leonardoDocument?.metadata.layout?.objects.last, other)
        XCTAssertEqual(session.leonardoDocument?.body, doc.body)
        XCTAssertEqual(session.rubricLibrary.entries.first?.rubric, ink)
        XCTAssertFalse(session.recolorInspectedGraphic(first, color: "#000000"), "Stale inspector snapshots cannot overwrite newer edits")
        XCTAssertFalse(session.recolorInspectedGraphic(updated, color: "<invalid>"))
        await session.undoDocument(); XCTAssertEqual(session.selectedGraphic, first)
        await session.redoDocument(); XCTAssertEqual(session.selectedGraphic, expected)
        await session.save()
        let reopened = try LeonardoFormatParser.parse(String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(reopened.metadata.layout?.objects.first, expected)
        XCTAssertEqual(reopened.body, doc.body)
    }

    func testSelectionLifecycleProtectionDeletionAndInvalidEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AppSession(preferencesURL: root.appendingPathComponent("prefs.json")); defer { session.stop() }
        session.documentURL = root.appendingPathComponent("one.mdlf"); session.documentKind = .leonardoTemplate
        let image = LeonardoGraphic(label: "Image", source: "assets/image.png")
        session.content = try LeonardoFormatParser.serialize(.init(body: "# Test", metadata: .init(layout: .init(objects: [image]))))
        session.isProtected = false
        session.receiveGraphicSelection(expected: session.content, id: image.id, inspect: true)
        XCTAssertEqual(session.selectedGraphic, image)
        let source = session.content
        XCTAssertFalse(session.recolorInspectedGraphic(image, color: "#000000"))
        XCTAssertFalse(session.updateInspectedGraphic(image) { $0.width = .nan })
        XCTAssertEqual(session.content, source)
        session.isProtected = true
        XCTAssertNil(session.selectedGraphicID); XCTAssertFalse(session.showsGraphicInspector)
        XCTAssertFalse(session.updateInspectedGraphic(image) { $0.z = 1 })
        session.isProtected = false
        session.receiveGraphicSelection(expected: session.content, id: image.id, inspect: true)
        session.mode = .fill
        XCTAssertNil(session.selectedGraphicID)
        session.mode = .preview
        session.receiveGraphicSelection(expected: session.content, id: image.id, inspect: true)
        session.documentURL = root.appendingPathComponent("two.mdlf")
        XCTAssertNil(session.selectedGraphicID)
        session.receiveGraphicSelection(expected: session.content, id: image.id, inspect: true)
        session.removeInspectedGraphic(image)
        XCTAssertNil(session.selectedGraphic); XCTAssertNil(session.selectedGraphicID)
        await session.undoDocument()
        XCTAssertEqual(session.leonardoDocument?.metadata.layout?.objects.first, image)
        XCTAssertNil(session.selectedGraphicID, "Undo must not resurrect dismissed chrome")
        session.receiveGraphicSelection(expected: session.content, id: "missing", inspect: true)
        XCTAssertFalse(session.showsGraphicInspector)
    }
}
