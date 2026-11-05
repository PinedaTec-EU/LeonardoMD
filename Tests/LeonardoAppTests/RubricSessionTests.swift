import AppKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class RubricSessionTests: XCTestCase {
    private var ink: LeonardoRubric {
        .init(strokes: [.init(color: "#224488", width: 3, style: .solid, points: [.init(x: 20, y: 40), .init(x: 300, y: 100)])])
    }
    func testLibraryPersistsAndDeletionDoesNotChangeInsertedValue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.json"), library = RubricLibrary(url: url)
        try library.add(label: "Inspection", rubric: ink)
        let inserted = try XCTUnwrap(library.entries.first)
        XCTAssertEqual(RubricLibrary(url: url).entries.first?.rubric, ink)
        try library.remove(id: inserted.id)
        XCTAssertTrue(RubricLibrary(url: url).entries.isEmpty)
        XCTAssertEqual(inserted.rubric, ink)
    }
    func testIndependentLibrariesMergeWritesAndFailClosedOnCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.json")
        let first = RubricLibrary(url: url), second = RubricLibrary(url: url)
        try first.add(label: "First", rubric: ink)
        let firstID = try XCTUnwrap(first.entries.first?.id)
        try second.add(label: "Second", rubric: ink)
        XCTAssertEqual(second.entries.map(\.label), ["First", "Second"])
        try first.remove(id: firstID)
        second.refresh()
        XCTAssertEqual(second.entries.map(\.label), ["Second"])
        let lock = try ProcessFileLock(at: ProcessFileLock.coordinationDirectory
            .appendingPathComponent(ProcessFileLock.key(for: url) + ".rubrics"))
        try withExtendedLifetime(lock) {
            XCTAssertThrowsError(try first.add(label: "Busy", rubric: ink))
        }
        XCTAssertEqual(RubricLibrary(url: url).entries.map(\.label), ["Second"])
        try Data("invalid".utf8).write(to: url, options: .atomic)
        XCTAssertThrowsError(try first.remove(id: firstID))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "invalid")
    }
    func testProtectionIdentityGeometryAndUndoShareDocumentHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.mdlf")
        let source = try LeonardoFormatParser.serialize(.init(body: "# Inspection"))
        try source.write(to: url, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("prefs.json")); session.authorizePath = { _, _ in }
        defer { session.stop() }
        await session.openDocument(url)
        let object = LeonardoGraphic(label: "Inspection", rubric: ink)
        XCTAssertFalse(session.insertGraphic(object))
        session.isProtected = false
        XCTAssertTrue(session.insertGraphic(object))
        let inserted = session.content
        var moved = object; moved.page = 2; moved.x = 99; moved.z = -1
        XCTAssertTrue(session.handleGraphicAction(expected: inserted, object: moved, remove: nil, fieldID: nil))
        XCTAssertEqual(session.leonardoDocument?.metadata.layout?.objects.first?.x, 99)
        XCTAssertFalse(session.handleGraphicAction(expected: inserted, object: moved, remove: nil, fieldID: nil))
        await session.undoDocument()
        XCTAssertEqual(session.content, inserted)
        await session.redoDocument()
        XCTAssertEqual(session.leonardoDocument?.metadata.layout?.objects.first?.z, -1)
        await session.save()
        XCTAssertEqual(try LeonardoFormatParser.parse(String(contentsOf: url, encoding: .utf8)).metadata.layout?.objects.first?.page, 2)
        session.mode = .fill
        XCTAssertFalse(session.handleGraphicAction(expected: session.content, object: object, remove: nil, fieldID: nil))
    }
    func testImportedTransparentImageSurvivesRelocatedPackageAndRejectsAssetSymlinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.mdlf")
        try LeonardoFormatParser.serialize(.init(body: "# Imported image")).write(to: url, atomically: true, encoding: .utf8)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 6,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.setColor(NSColor.red.withAlphaComponent(0.5), atX: 2, y: 2)
        let image = root.appendingPathComponent("input.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: image)
        let session = AppSession(preferencesURL: root.appendingPathComponent("prefs.json")); session.authorizePath = { _, _ in }
        defer { session.stop() }
        await session.openDocument(url); session.isProtected = false
        await session.importGraphicImage(image)
        let object = try XCTUnwrap(session.leonardoDocument?.metadata.layout?.objects.first)
        XCTAssertEqual(object.height, 90)
        XCTAssertTrue(try XCTUnwrap(object.source).hasPrefix("assets/"))
        let asset = root.appendingPathComponent(try XCTUnwrap(object.source))
        let normalized = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: asset)))
        XCTAssertTrue(normalized.hasAlpha)
        let package = root.appendingPathComponent("portable.mdlz")
        try LeonardoPackageTransport.export(documentURL: url, content: session.content, to: package)
        let elsewhere = root.appendingPathComponent("relocated")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let moved = elsewhere.appendingPathComponent("portable.mdlz")
        try FileManager.default.moveItem(at: package, to: moved)
        try FileManager.default.removeItem(at: image)
        let workspace = try LeonardoPackageTransport.open(moved)
        defer { LeonardoPackageTransport.discard(workspace) }
        let document = try LeonardoFormatParser.parse(String(contentsOf: workspace.documentURL, encoding: .utf8))
        let portable = try XCTUnwrap(document.metadata.layout?.objects.first)
        XCTAssertEqual(portable.x, object.x); XCTAssertEqual(portable.z, object.z)
        XCTAssertEqual(try Data(contentsOf: workspace.directoryURL.appendingPathComponent(XCTUnwrap(portable.source))), try Data(contentsOf: asset))
        _ = try LeonardoPackageTransport.save(workspace)
        let unsafe = root.appendingPathComponent("unsafe")
        try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: unsafe.appendingPathComponent("assets"), withDestinationURL: elsewhere)
        XCTAssertThrowsError(try GraphicAssetStore.create(Data([1]), name: "image-ABC.png", beside: unsafe.appendingPathComponent("doc.mdlf")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("image-ABC.png").path))
    }

    func testProtectedFormOpensOnlyDeclaredWritableRubricFields() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.mdlr")
        let document = LeonardoDocument(body: "{{field:signature}}", metadata: .init(fields: ["signature": .init(type: .rubric), "locked": .init(type: .rubric, readOnly: true)]))
        try LeonardoFormatParser.serialize(document).write(to: url, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("prefs.json")); session.authorizePath = { _, _ in }
        defer { session.stop() }
        await session.openDocument(url); session.mode = .fill; session.isProtected = true
        session.requestRubric(fieldID: "locked"); XCTAssertNil(session.rubricRequest)
        session.requestRubric(fieldID: "signature")
        let request = try XCTUnwrap(session.rubricRequest)
        XCTAssertTrue(session.finishRubric(request, label: "Test", rubric: ink, saveToLibrary: false))
        XCTAssertEqual(LeonardoRubric.decode(session.leonardoFieldValue("signature")), ink)
        XCTAssertEqual(session.leonardoDocument?.body, document.body)
        XCTAssertEqual(session.leonardoDocument?.metadata.fields, document.metadata.fields)
        XCTAssertFalse(session.finishRubric(request, label: "Stale", rubric: ink, saveToLibrary: false))
    }
}
