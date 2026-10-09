#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

final class DesktopPeerProposalTransportTests: XCTestCase {
    func testRealPinnedProposalDeliveryRetryRestartAndRevocationNeverWritesSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Source/docs/note.md")
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original source".utf8).write(to: original)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Source notes", scope: try CorpusScope(folder: ""), selection: selection)
        let baseline = CorpusSnapshot(revision: "source", files: [CorpusFile(path: "docs/note.md", content: Data("original source".utf8))])
        let reader = ProjectCorpusReader()
        let sourceRoot = original.deletingLastPathComponent().deletingLastPathComponent()
        let source = SharedProjectSource(descriptor: descriptor) { try await reader.snapshot(root: sourceRoot, selection: selection) }
        let serviceRoot = root.appendingPathComponent("Service")
        let runtime = DesktopDirectRuntime(root: serviceRoot, credentials: ProposalMemoryCredentials(), now: { Date() })
        var running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [source])
        do {
            let credential = try PairingRegistry.makeCredential()
            let enrollment = try DirectEnrollmentClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            let paired = try await enrollment.begin(deviceName: "MacBook", credential: credential, now: Date(), kind: .desktopPeer)
            try await runtime.approve(requestID: paired.deviceID, code: paired.comparisonCode, projectIDs: [descriptor.id])
            let proposal = try DesktopPeerProposal(projectID: descriptor.id, selection: selection, base: baseline,
                proposed: CorpusSnapshot(revision: "incoming", files: [CorpusFile(path: "docs/note.md", content: Data(repeating: 66, count: 80_000))]))
            let client = try DesktopPeerProposalClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            try await client.submit(proposal, deviceID: paired.deviceID, credential: credential)
            try await client.submit(proposal, deviceID: paired.deviceID, credential: credential)
            let pending = try await runtime.incomingProposals()
            XCTAssertEqual(pending.count, 1)
            XCTAssertEqual(pending.first?.deviceID, paired.deviceID)
            let upload = try XCTUnwrap(pending.first?.upload)
            let received = try await runtime.incomingProposal(deviceID: paired.deviceID, upload: upload)
            XCTAssertEqual(received, proposal)
            try Data("source edited independently".utf8).write(to: original)
            let review = try await runtime.reviewIncomingProposal(deviceID: paired.deviceID, upload: upload)
            XCTAssertEqual(review.source.files.first?.content, Data("source edited independently".utf8))
            XCTAssertEqual(review.comparison.differences.first?.path, "docs/note.md")
            XCTAssertTrue(review.comparison.differences.first?.hasConflict == true)
            try Data("original source".utf8).write(to: original)
            XCTAssertEqual(try Data(contentsOf: original), Data("original source".utf8))
            try await runtime.stop()
            running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [source])
            let reopened = try await runtime.incomingProposals()
            XCTAssertEqual(reopened.first?.upload, upload)
            let reopenedPayload = try await runtime.incomingProposal(deviceID: paired.deviceID, upload: upload)
            XCTAssertEqual(reopenedPayload, proposal)
            let newClient = try DesktopPeerProposalClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            try await newClient.submit(proposal, deviceID: paired.deviceID, credential: credential)
            let secondCredential = try PairingRegistry.makeCredential()
            let secondEnrollment = try DirectEnrollmentClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            let second = try await secondEnrollment.begin(deviceName: "Other Mac", credential: secondCredential, now: Date(), kind: .desktopPeer)
            try await runtime.approve(requestID: second.deviceID, code: second.comparisonCode, projectIDs: [descriptor.id])
            try await newClient.submit(proposal, deviceID: second.deviceID, credential: secondCredential)
            let independent = try await runtime.incomingProposals()
            XCTAssertEqual(independent.count, 2)
            XCTAssertEqual(Set(independent.map(\.id)).count, 2) // Even a reused proposal ID cannot alias another authenticated sender.
            try await runtime.revoke(deviceID: paired.deviceID)
            do { try await newClient.submit(proposal, deviceID: paired.deviceID, credential: credential); XCTFail("Revoked sender submitted") }
            catch { XCTAssertEqual(error as? DesktopPeerProposalTransportError, .accessDenied) }
            let denied = try await runtime.incomingProposals()
            XCTAssertEqual(denied.map(\.deviceID), [second.deviceID])
            do { _ = try await runtime.incomingProposal(deviceID: paired.deviceID, upload: upload); XCTFail("Revoked proposal reviewed") }
            catch { XCTAssertEqual(error as? SyncError, .revoked) }
            XCTAssertEqual(try Data(contentsOf: original), Data("original source".utf8))
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }

    func testReadOnlyClientCannotCreateProposalStagingViaRealHTTPS() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Read only", scope: try CorpusScope(folder: ""), selection: selection)
        let snapshot = CorpusSnapshot(revision: "empty", files: [])
        let runtime = DesktopDirectRuntime(root: root, credentials: ProposalMemoryCredentials(), now: { Date() })
        let running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [SharedProjectSource(descriptor: descriptor) { snapshot }])
        do {
            let credential = try PairingRegistry.makeCredential()
            let enrollment = try DirectEnrollmentClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            let paired = try await enrollment.begin(deviceName: "Mobile", credential: credential, now: Date())
            try await runtime.approve(requestID: paired.deviceID, code: paired.comparisonCode, projectIDs: [descriptor.id])
            let proposal = try DesktopPeerProposal(projectID: descriptor.id, selection: selection, base: snapshot, proposed: snapshot)
            let client = try DesktopPeerProposalClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            do { try await client.submit(proposal, deviceID: paired.deviceID, credential: credential); XCTFail("Read-only sender published") }
            catch { XCTAssertEqual(error as? DesktopPeerProposalTransportError, .accessDenied) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Proposals").path))
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }
}
private actor ProposalMemoryCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values[deviceID] = nil }
}
#endif
