import Foundation
import XCTest
@testable import LeonardoCore

final class DocumentStoreTests: XCTestCase {
    func testSaveDetectsExternalChanges() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("note.md")
        let store = DocumentStore()

        let first = try await store.save("first", to: url)
        let unchanged = await store.hasChanged(first)
        XCTAssertFalse(unchanged)
        try Data("external".utf8).write(to: url, options: [.atomic])
        let changed = await store.hasChanged(first)
        XCTAssertTrue(changed)

        do {
            _ = try await store.save("local", to: url, expectedFingerprint: first.fingerprint)
            XCTFail("Expected external edit conflict")
        } catch let error as DocumentStoreError {
            guard case let .conflict(expected, current) = error else {
                return XCTFail("Unexpected document error: \(error)")
            }
            XCTAssertEqual(expected, first.fingerprint)
            XCTAssertEqual(current?.content, "external")
        }

        let external = try await store.read(url)
        let saved = try await store.save("local", to: url, expectedFingerprint: external.fingerprint)
        XCTAssertEqual(saved.content, "local")
    }
}
