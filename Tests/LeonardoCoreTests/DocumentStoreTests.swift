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

    func testCreateNewPreservesExistingDestination() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("note.md")
        try Data("existing".utf8).write(to: url, options: [.atomic])
        let store = DocumentStore()

        do {
            _ = try await store.createNew("replacement", to: url)
            XCTFail("Expected an existing destination error")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .itemAlreadyExists(url.standardizedFileURL))
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "existing")
    }

    func testCreateNewPreservesSymlinkDestinationAndTarget() async throws {
        let directory = try TemporaryDirectory()
        let targetURL = directory.url.appendingPathComponent("target.md")
        let linkURL = directory.url.appendingPathComponent("alias.md")
        try Data("target".utf8).write(to: targetURL, options: [.atomic])
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        let store = DocumentStore()

        do {
            _ = try await store.createNew("replacement", to: linkURL)
            XCTFail("Expected a symlink destination error")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .itemAlreadyExists(linkURL.standardizedFileURL))
        }
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "target")
    }

    func testCreateNewRejectsChangedSourceWithoutCreatingDestination() async throws {
        let directory = try TemporaryDirectory()
        let sourceURL = directory.url.appendingPathComponent("source.md")
        let destinationURL = directory.url.appendingPathComponent("copy.md")
        try Data("source".utf8).write(to: sourceURL, options: [.atomic])
        let store = DocumentStore()
        let source = try await store.read(sourceURL)
        try Data("changed".utf8).write(to: sourceURL, options: [.atomic])

        do {
            _ = try await store.createNew("copy", to: destinationURL, preserving: source)
            XCTFail("Expected a source fingerprint conflict")
        } catch let error as DocumentStoreError {
            guard case let .conflict(expected, current) = error else {
                return XCTFail("Unexpected document error: \(error)")
            }
            XCTAssertEqual(expected, source.fingerprint)
            XCTAssertEqual(current?.content, "changed")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testConcurrentCreateNewAllowsOnlyOneCreatorToWin() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("race.md")
        let firstStore = DocumentStore()
        let secondStore = DocumentStore()

        let winners = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            group.addTask {
                do {
                    return try await firstStore.createNew("first", to: url).content
                } catch {
                    return nil
                }
            }
            group.addTask {
                do {
                    return try await secondStore.createNew("second", to: url).content
                } catch {
                    return nil
                }
            }

            var values: [String] = []
            for await value in group {
                if let value { values.append(value) }
            }
            return values
        }

        XCTAssertEqual(winners.count, 1)
        guard let winner = winners.first else { return XCTFail("Expected one successful creator") }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), winner)
    }
}
