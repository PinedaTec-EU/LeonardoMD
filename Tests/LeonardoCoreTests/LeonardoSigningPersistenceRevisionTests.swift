import Foundation
import XCTest
@testable import LeonardoCore

final class LeonardoSigningPersistenceRevisionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testHistoricalRevisionsSharePathButCompetingRevisionIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LeonardoSigningStore(directoryURL: directory)
        let location = "/Users/example/private.mdlf"
        let first = try LeonardoGuidedSigningSession(
            document: makeDocument(revision: 1), at: now, documentLocation: location
        )
        try await store.saveSession(first)

        let secondDocument = makeDocument(revision: 2)
        let second = try LeonardoGuidedSigningSession(
            document: secondDocument, at: now.addingTimeInterval(1), documentLocation: location
        )
        try await store.saveSession(second)
        let sessionsAfterSecond = try await store.sessions()
        XCTAssertEqual(sessionsAfterSecond.count, 2)

        let competing = try LeonardoGuidedSigningSession(
            document: secondDocument, at: now.addingTimeInterval(2), documentLocation: location
        )
        do {
            try await store.saveSession(competing)
            XCTFail("A second session for the same document revision must be rejected")
        } catch let error as LeonardoSigningError {
            XCTAssertEqual(error, .staleStorage)
        }

        let third = try LeonardoGuidedSigningSession(
            document: makeDocument(revision: 3), at: now.addingTimeInterval(3), documentLocation: location
        )
        try await store.saveSession(third)

        let stored = try await store.sessions()
        XCTAssertEqual(stored.compactMap(\.initialRevision).sorted(), [1, 2, 3])
        XCTAssertTrue(stored.contains(where: { $0.id == first.id }))
        XCTAssertTrue(stored.contains(where: { $0.id == second.id }))
        XCTAssertTrue(stored.contains(where: { $0.id == third.id }))
    }

    func testStaleStoreKeepsUnrelatedProgressButRejectsTargetConflict() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStore = LeonardoSigningStore(directoryURL: directory)
        let secondStore = LeonardoSigningStore(directoryURL: directory)
        let location = "/Users/example/private.mdlf"
        let first = try LeonardoGuidedSigningSession(
            document: makeDocument(revision: 1), at: now, documentLocation: location
        )
        try await firstStore.saveSession(first)

        // The second instance retains a baseline for the first document.
        let staleValue = try await secondStore.session(id: first.id)
        let staleBaseline = try XCTUnwrap(staleValue)
        let unrelated = try LeonardoGuidedSigningSession(
            document: makeDocument(revision: 2),
            at: now.addingTimeInterval(1),
            documentLocation: location
        )
        try await firstStore.saveSession(unrelated)

        var updatedFirst = staleBaseline
        updatedFirst.updatedAt = now.addingTimeInterval(2)
        try await secondStore.saveSession(updatedFirst)

        let retained = try await secondStore.sessions()
        XCTAssertEqual(retained.count, 2)
        XCTAssertEqual(retained.first(where: { $0.id == first.id })?.updatedAt, updatedFirst.updatedAt)
        XCTAssertNotNil(retained.first(where: { $0.id == unrelated.id }))

        var staleUpdate = staleBaseline
        staleUpdate.updatedAt = now.addingTimeInterval(3)
        do {
            try await firstStore.saveSession(staleUpdate)
            XCTFail("A stale edit of the same session must not overwrite progress")
        } catch let error as LeonardoSigningError {
            XCTAssertEqual(error, .staleStorage)
        }
        let final = try await secondStore.sessions()
        XCTAssertEqual(final.first(where: { $0.id == first.id })?.updatedAt, updatedFirst.updatedAt)
        XCTAssertNotNil(final.first(where: { $0.id == unrelated.id }))
    }

    func testExplicitBaselineRejectsStaleWorkflowAfterStoreRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LeonardoSigningStore(directoryURL: directory)
        let original = try LeonardoGuidedSigningSession(document: makeDocument(revision: 1), at: now)
        try await store.saveSession(original, replacing: nil)

        var newer = original
        newer.updatedAt = now.addingTimeInterval(1)
        try await store.saveSession(newer, replacing: original)
        _ = try await store.session(id: original.id)

        var stale = original
        stale.updatedAt = now.addingTimeInterval(2)
        do {
            try await store.saveSession(stale, replacing: original)
            XCTFail("Refreshing the store must not advance an open workflow’s write baseline")
        } catch let error as LeonardoSigningError {
            XCTAssertEqual(error, .staleStorage)
        }
        let stored = try await store.session(id: original.id)
        XCTAssertEqual(stored, newer)
    }

    func testPristineReplacementUsesExplicitCallerBaseline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStore = LeonardoSigningStore(directoryURL: directory)
        let secondStore = LeonardoSigningStore(directoryURL: directory)
        let location = "/Users/example/private.mdlf"
        let document = makeDocument(revision: 1)
        let local = try LeonardoGuidedSigningSession(
            document: document, at: now, documentLocation: location
        )
        try await firstStore.saveSession(local, replacing: nil)
        let baselineValue = try await secondStore.session(id: local.id)
        let baseline = try XCTUnwrap(baselineValue)
        let imported = try LeonardoGuidedSigningSession(
            document: document, at: now.addingTimeInterval(1), documentLocation: location
        )
        try await firstStore.replacePristineSession(id: local.id, with: imported)

        let staleReplacement = try LeonardoGuidedSigningSession(
            document: document, at: now.addingTimeInterval(2), documentLocation: location
        )
        do {
            try await secondStore.replacePristineSession(
                id: local.id,
                baseline: baseline,
                with: staleReplacement
            )
            XCTFail("A replacement must compare the caller's baseline inside the transaction")
        } catch let error as LeonardoSigningError {
            XCTAssertEqual(error, .staleStorage)
        }
        let stored = try await firstStore.session(id: imported.id)
        XCTAssertEqual(stored, imported)
    }

    private func makeDocument(revision: Int) -> LeonardoDocument {
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "signer", label: "Signer")
        ])
        return LeonardoDocument(
            body: "{{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "guided-form",
                    title: "Guided form",
                    kind: .form,
                    revision: revision,
                    signing: declaration
                ),
                fields: [
                    "signature": LeonardoFieldDefinition(
                        type: .rubric,
                        signerPosition: "signer"
                    )
                ]
            )
        )
    }
}
