#if os(macOS)
import XCTest
import CryptoKit
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

final class DesktopPeerProposalTransportTests: XCTestCase {
    func testRealPinnedProposalDeliveryOwnerAcceptanceRetryRestartAndRevocation() async throws {
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
        let source = SharedProjectSource(descriptor: descriptor, rootURL: sourceRoot) { try await reader.snapshot(root: sourceRoot, selection: selection) }
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
            let missingReceipt = try await client.receipt(proposalID: proposal.id, projectID: descriptor.id, selection: selection, deviceID: paired.deviceID, credential: credential)
            XCTAssertNil(missingReceipt)
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
            // This filesystem fixture owns all writes exclusively; native editor leases are separate.
            let freshReview = try await runtime.reviewIncomingProposal(deviceID: paired.deviceID, upload: upload)
            do {
                _ = try await runtime.acceptIncomingProposal(deviceID: paired.deviceID, upload: upload, review: freshReview,
                    decisions: ["docs/note.md": .remote], projectRoot: root, currentSource: freshReview.source, currentDisk: baseline)
                XCTFail("Applied to a root outside the configured source")
            } catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }
            let receipt = try await runtime.acceptIncomingProposal(deviceID: paired.deviceID, upload: upload, review: freshReview,
                decisions: ["docs/note.md": .local], projectRoot: sourceRoot, currentSource: freshReview.source, currentDisk: baseline)
            XCTAssertEqual(receipt.accepted.files, proposal.proposed.files)
            XCTAssertEqual(try Data(contentsOf: original), proposal.proposed.files[0].content)
            try Data("later source bytes".utf8).write(to: original)
            let downloaded = try await newClient.receipt(proposalID: proposal.id, projectID: descriptor.id, selection: selection, deviceID: paired.deviceID, credential: credential)
            XCTAssertEqual(downloaded, receipt)
            let incorrectReceipt = try DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: descriptor.id,
                accepted: CorpusSnapshot(revision: "incorrect", files: baseline.files))
            do {
                try await newClient.acknowledge(proposal, receipt: incorrectReceipt, deviceID: paired.deviceID, credential: credential)
                XCTFail("An incorrect receipt closed the proposal")
            } catch { XCTAssertEqual(error as? TransportError, .unexpectedResponse) }
            try await newClient.acknowledge(proposal, receipt: receipt, deviceID: paired.deviceID, credential: credential)
            try await newClient.acknowledge(proposal, receipt: receipt, deviceID: paired.deviceID, credential: credential)
            let nextProposal = try DesktopPeerProposal(projectID: descriptor.id, selection: selection,
                base: receipt.accepted, proposed: receipt.accepted)
            try await newClient.submit(nextProposal, deviceID: paired.deviceID, credential: credential)
            // A delayed ACK of the old result cannot remove the newly submitted slot.
            try await newClient.acknowledge(proposal, receipt: receipt, deviceID: paired.deviceID, credential: credential)
            let nextPending = try await runtime.incomingProposals()
            XCTAssertEqual(nextPending.map(\.upload.proposalID), [nextProposal.id])
            do {
                try await newClient.submit(proposal, deviceID: paired.deviceID, credential: credential)
                XCTFail("An acknowledged proposal was recreated")
            } catch { XCTAssertEqual(error as? SyncError, .publicationPending) }
            let secondCredential = try PairingRegistry.makeCredential()
            let secondEnrollment = try DirectEnrollmentClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            let second = try await secondEnrollment.begin(deviceName: "Other Mac", credential: secondCredential, now: Date(), kind: .desktopPeer)
            try await runtime.approve(requestID: second.deviceID, code: second.comparisonCode, projectIDs: [descriptor.id])
            try await newClient.submit(proposal, deviceID: second.deviceID, credential: secondCredential)
            let otherDeviceReceipt = try await newClient.receipt(proposalID: proposal.id, projectID: descriptor.id, selection: selection, deviceID: second.deviceID, credential: secondCredential)
            XCTAssertNil(otherDeviceReceipt)

            let independent = try await runtime.incomingProposals()
            XCTAssertEqual(independent.count, 2)
            XCTAssertEqual(Set(independent.map(\.deviceID)), [paired.deviceID, second.deviceID])
            XCTAssertEqual(Set(independent.map(\.id)).count, 2) // Even a reused proposal ID cannot alias another authenticated sender.
            try await runtime.revoke(deviceID: paired.deviceID)
            do { try await newClient.submit(proposal, deviceID: paired.deviceID, credential: credential); XCTFail("Revoked sender submitted") }
            catch { XCTAssertEqual(error as? DesktopPeerProposalTransportError, .accessDenied) }
            do {
                _ = try await newClient.receipt(proposalID: proposal.id, projectID: descriptor.id, selection: selection, deviceID: paired.deviceID, credential: credential)
                XCTFail("Revoked sender received receipt")
            } catch { XCTAssertEqual(error as? DesktopPeerProposalTransportError, .accessDenied) }
            let denied = try await runtime.incomingProposals()
            XCTAssertEqual(denied.map(\.deviceID), [second.deviceID])
            do { _ = try await runtime.incomingProposal(deviceID: paired.deviceID, upload: upload); XCTFail("Revoked proposal reviewed") }
            catch { XCTAssertEqual(error as? SyncError, .revoked) }
            XCTAssertEqual(try Data(contentsOf: original), Data("later source bytes".utf8))
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
            let fakeReceipt = try DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: descriptor.id, accepted: snapshot)
            do {
                try await client.acknowledge(proposal, receipt: fakeReceipt, deviceID: paired.deviceID, credential: credential)
                XCTFail("Read-only client acknowledged a proposal")
            } catch { XCTAssertEqual(error as? DesktopPeerProposalTransportError, .accessDenied) }
            do {
                _ = try await client.receipt(proposalID: proposal.id, projectID: descriptor.id, selection: selection, deviceID: paired.deviceID, credential: credential)
                XCTFail("Read-only client queried reconciliation receipts")
            } catch { XCTAssertEqual(error as? DesktopPeerProposalTransportError, .accessDenied) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Proposals").path))
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }

    func testReadCapabilityHeaderCannotEnableLeonardoFormatPeerWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source")
        let markdown = sourceRoot.appendingPathComponent("docs/note.md")
        let form = sourceRoot.appendingPathComponent("docs/form.mdlf")
        try FileManager.default.createDirectory(at: markdown.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("source note".utf8).write(to: markdown)
        let originalForm = Data("form baseline".utf8)
        try originalForm.write(to: form)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Mixed source",
            scope: try CorpusScope(folder: ""), selection: selection)
        let reader = ProjectCorpusReader()
        let source = SharedProjectSource(descriptor: descriptor, rootURL: sourceRoot) {
            try await reader.snapshot(root: sourceRoot, selection: selection)
        }
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Server"),
            credentials: ProposalMemoryCredentials(), now: { Date() })
        let running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [source])
        do {
            let credential = try PairingRegistry.makeCredential()
            let enrollment = try DirectEnrollmentClient(endpoint: running.endpoint,
                certificateFingerprint: running.certificateFingerprint)
            let paired = try await enrollment.begin(deviceName: "Read-only-capable peer", credential: credential,
                now: Date(), kind: .desktopPeer)
            try await runtime.approve(requestID: paired.deviceID, code: paired.comparisonCode,
                projectIDs: [descriptor.id])

            let base = CorpusSnapshot(revision: "base", files: [
                CorpusFile(path: "docs/note.md", content: Data("source note".utf8)),
                CorpusFile(path: "docs/form.mdlf", content: originalForm)
            ])
            let proposed = CorpusSnapshot(revision: "proposed", files: [
                CorpusFile(path: "docs/note.md", content: Data("source note".utf8)),
                CorpusFile(path: "docs/form.mdlf", content: Data("changed form".utf8))
            ])
            let proposal = try DesktopPeerProposal(projectID: descriptor.id, selection: selection,
                base: base, proposed: proposed)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let bytes = try encoder.encode(proposal)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let upload = try DesktopPeerUpload(proposalID: proposal.id, projectID: proposal.projectID,
                byteCount: bytes.count, sha256: digest)
            let transport = try PinnedHTTPSClient(endpoint: running.endpoint,
                certificateFingerprint: running.certificateFingerprint,
                maximumResponseBytes: DesktopPeerArchiveBudget.maximumEncodedBytes(), allowPrivateOverlay: true)
            let path = "/v1/devices/\(paired.deviceID.uuidString)/projects/\(descriptor.id.uuidString)/proposals/"
            let started = try await transport.request(method: "POST", path: path + "begin", credential: credential,
                body: encoder.encode(upload), supportsReadOnlyLeonardoFormats: true)
            XCTAssertEqual(started.status, 200)

            var offset = 0
            while offset < bytes.count {
                let end = min(bytes.count, offset + DesktopPeerUpload.maximumChunkBytes)
                let chunk = DesktopPeerUploadChunk(upload: upload, offset: offset, bytes: bytes.subdata(in: offset..<end))
                let response = try await transport.request(method: "POST", path: path + "chunk", credential: credential,
                    body: encoder.encode(chunk), supportsReadOnlyLeonardoFormats: true)
                XCTAssertEqual(response.status, 200)
                offset = end
            }
            let submitted = try await transport.request(method: "POST", path: path + "submit", credential: credential,
                body: encoder.encode(upload), supportsReadOnlyLeonardoFormats: true)
            XCTAssertEqual(submitted.status, 400,
                           "A read-only format capability must not authorize an excluded peer write")
            XCTAssertEqual(try Data(contentsOf: form), originalForm)
            let incoming = try await runtime.incomingProposals()
            XCTAssertTrue(incoming.isEmpty, "Rejected payloads are not published for owner review")
            try await runtime.stop()
        } catch {
            try? await runtime.stop()
            throw error
        }
    }
}
private actor ProposalMemoryCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values[deviceID] = nil }
}
#endif
