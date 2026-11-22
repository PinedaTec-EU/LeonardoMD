import Foundation
import XCTest
@testable import LeonardoCore

final class LeonardoSigningShardRecoveryTests: XCTestCase {
    func testCommittedReplacementRemainsWholeWhenShardCannotBeWritten() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LeonardoSigningStore(directoryURL: directory)
        let previous = try makeSession()
        let replacement = try makeSession()
        try await store.saveSession(previous)

        let shards = directory.appendingPathComponent("signing-progress", isDirectory: true)
        let blockedShard = shards.appendingPathComponent("\(replacement.id.uuidString).json")
        let journal = shards.appendingPathComponent(".transaction.json")
        try FileManager.default.createDirectory(at: blockedShard, withIntermediateDirectories: false)

        // Call the disk commit point directly to introduce the obstruction
        // after the actor has compared the old session and prepared its update.
        let transaction = try LeonardoSigningSessionShardStore.SessionTransaction(records: [
            previous.id: .tombstone,
            replacement.id: .init(session: replacement)
        ])
        try LeonardoSigningSessionShardStore.applySessionTransaction(transaction, to: shards)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))

        let reopened = LeonardoSigningStore(directoryURL: directory)
        let committed = try await reopened.sessions()
        XCTAssertEqual(committed, [replacement])

        try FileManager.default.removeItem(at: blockedShard)
        var advanced = replacement
        advanced.updatedAt = replacement.updatedAt.addingTimeInterval(1)
        try await reopened.saveSession(advanced, replacing: replacement)

        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        let recovered = try await store.sessions()
        XCTAssertEqual(recovered, [advanced])
    }

    func testCorruptShardCannotMasqueradeAsAnUnsignedDocument() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LeonardoSigningStore(directoryURL: directory)
        let session = try makeSession()
        try await store.saveSession(session)
        let shard = directory.appendingPathComponent("signing-progress/\(session.id.uuidString).json")
        try Data("truncated".utf8).write(to: shard)

        do {
            _ = try await store.hasSession(documentLocation: try XCTUnwrap(session.documentLocation))
            XCTFail("Unreadable progress must not be reported as absent")
        } catch let error as LeonardoSigningError {
            XCTAssertEqual(error, .storageFailure)
        }
    }

    private func makeSession() throws -> LeonardoGuidedSigningSession {
        let descriptor = LeonardoDocumentDescriptor(
            id: "review",
            title: "Review",
            kind: .form,
            revision: 1,
            signing: LeonardoSigningDeclaration(positions: [
                LeonardoSignerPosition(id: "reviewer", label: "Reviewer")
            ])
        )
        let document = LeonardoDocument(
            body: "{{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: descriptor,
                fields: ["signature": LeonardoFieldDefinition(type: .rubric, signerPosition: "reviewer")]
            )
        )
        return try LeonardoGuidedSigningSession(
            document: document, at: Date(timeIntervalSince1970: 123), documentLocation: "/example/review.mdlf"
        )
    }
}
