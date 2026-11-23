#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

final class DesktopPeerLibraryTests: XCTestCase {
    func testRealPinnedHTTPSLibraryConsumesReceiptPreservesLaterEditsAndAllowsNextProposal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source")
        let sourceFile = sourceRoot.appendingPathComponent("docs/note.md")
        try FileManager.default.createDirectory(at: sourceFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("source baseline".utf8).write(to: sourceFile)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Receipt source", scope: try CorpusScope(folder: ""), selection: selection)
        let reader = ProjectCorpusReader()
        let source = SharedProjectSource(descriptor: descriptor, rootURL: sourceRoot) {
            try await reader.snapshot(root: sourceRoot, selection: selection)
        }
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Server"), credentials: PeerMemoryCredentials(), now: { Date() })
        let running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [source])
        do {
            let connectionStore = FileDesktopPeerConnectionStore(root: root.appendingPathComponent("Connections"))
            let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
            let workingRoot = root.appendingPathComponent("Working")
            let workspace = DesktopPeerWorkspace(root: workingRoot, copies: copies)
            let outbox = FileDesktopPeerOutboxStore(root: root.appendingPathComponent("Outbox"))
            let intents = FileDesktopPeerReceiptIntentStore(root: root.appendingPathComponent("ReceiptIntents"))
            let applier = DesktopPeerReceiptApplier(workingRoot: workingRoot, copies: copies, intents: intents)
            let credentials = PeerMemoryCredentials()
            let revoker = PeerRevokerFixture()
            let library = DesktopPeerLibrary(connections: connectionStore, copies: copies, workspace: workspace,
                credentials: credentials, remote: DesktopPeerHTTPSRemote(), revoker: revoker,
                outbox: outbox, receiptApplier: applier)
            let connection = try await library.enroll(endpoint: running.endpoint, fingerprint: nil, invitation: nil, name: "MacBook receipts")
            let registry = try await runtime.consentState()
            let request = try XCTUnwrap(registry.requests.first)
            try await runtime.approve(requestID: request.id, code: request.comparisonCode, projectIDs: [descriptor.id])
            let copy = try await library.importProject(connectionID: connection.id, projectID: descriptor.id)
            let directory = try await library.open(copyID: copy.id)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/note.md")), Data("source baseline".utf8))

            let sent = try await library.send(copyID: copy.id,
                buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "proposal draft")])
            let firstID = try XCTUnwrap(sent)
            let pendingValue = try await library.pendingProposal(copyID: copy.id)
            let pending = try XCTUnwrap(pendingValue)
            XCTAssertEqual(pending.proposal.id, firstID)
            let incomingValues = try await runtime.incomingProposals()
            let incoming = try XCTUnwrap(incomingValues.first)
            let review = try await runtime.reviewIncomingProposal(deviceID: incoming.deviceID, upload: incoming.upload)
            let ownerDisk = try await reader.snapshot(root: sourceRoot, selection: selection)
            let acceptedResult = try await runtime.applyIncomingProposal(deviceID: incoming.deviceID, upload: incoming.upload,
                review: review, decisions: ["docs/note.md": .local], projectRoot: sourceRoot,
                currentSource: review.source, currentDisk: ownerDisk)
            let receipt = acceptedResult.receipt
            XCTAssertEqual(receipt.accepted.files.first?.content, Data("proposal draft".utf8))
            XCTAssertEqual(try Data(contentsOf: sourceFile), Data("proposal draft".utf8))

            // These bytes are created after the immutable proposal was sent. The open
            // buffer must survive receipt application while the saved disk bytes remain.
            try Data("later saved".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
            try Data("later addition".utf8).write(to: directory.appendingPathComponent("docs/later.md"))
            let downloadedValue = try await library.pendingReceipt(copyID: copy.id)
            let downloaded = try XCTUnwrap(downloadedValue)
            XCTAssertEqual(downloaded, receipt)
            let applied = try await library.acknowledge(copyID: copy.id, receipt: downloaded,
                buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "later draft")])
            XCTAssertTrue(applied.appliedNow)
            XCTAssertEqual(applied.retainedBufferPaths, ["docs/note.md"])
            XCTAssertEqual(applied.appliedSnapshot.files.first { $0.path == "docs/note.md" }?.content, Data("later saved".utf8))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/note.md")), Data("later saved".utf8))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/later.md")), Data("later addition".utf8))
            let acknowledgedValue = try await copies.load(id: copy.id)
            let acknowledged = try XCTUnwrap(acknowledgedValue)
            XCTAssertEqual(acknowledged.base, receipt.accepted)
            XCTAssertEqual(acknowledged.files.first { $0.path == "docs/note.md" }?.content, Data("later draft".utf8))
            XCTAssertTrue(acknowledged.files.first { $0.path == "docs/note.md" }?.isUnsavedBuffer == true)
            XCTAssertFalse(acknowledged.files.first { $0.path == "docs/later.md" }?.isUnsavedBuffer == true)
            let clearedIncoming = try await runtime.incomingProposals()
            XCTAssertTrue(clearedIncoming.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Outbox").appendingPathComponent(copy.id.uuidString).appendingPathExtension("json").path))

            // Reopen the client from its durable stores and submit another proposal in
            // the same device/project slot after the first ACK has closed it.
            let reopenedWorkspace = DesktopPeerWorkspace(root: workingRoot, copies: copies)
            let reopenedApplier = DesktopPeerReceiptApplier(workingRoot: workingRoot, copies: copies,
                intents: FileDesktopPeerReceiptIntentStore(root: root.appendingPathComponent("ReceiptIntents")))
            let reopenedRevoker = PeerRevokerFixture()
            let reopened = DesktopPeerLibrary(connections: connectionStore, copies: copies, workspace: reopenedWorkspace,
                credentials: credentials, remote: DesktopPeerHTTPSRemote(), revoker: reopenedRevoker,
                outbox: outbox, receiptApplier: reopenedApplier)
            let reopenedDirectory = try await reopened.open(copyID: copy.id)
            XCTAssertEqual(reopenedDirectory, directory)
            let secondSent = try await reopened.send(copyID: copy.id,
                buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "second draft")])
            let secondID = try XCTUnwrap(secondSent)
            XCTAssertNotEqual(secondID, firstID)
            let secondIncoming = try await runtime.incomingProposals()
            XCTAssertEqual(secondIncoming.map(\.upload.proposalID), [secondID])

            try await runtime.revoke(deviceID: connection.remoteDeviceID)
            let revoked = try await reopened.refresh(connectionID: connection.id)
            XCTAssertEqual(revoked.access, .revoked)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            let clearedOutbox = try await outbox.load(copyID: copy.id)
            XCTAssertNil(clearedOutbox)
            let closedIDs = await reopenedRevoker.closedIDs
            XCTAssertTrue(closedIDs.contains(copy.id))
            try await runtime.stop()
        } catch {
            try? await runtime.stop()
            throw error
        }
    }

    func testExpandedGrantKeepsLegacyProposalPinnedThroughOwnerReceiptRestartAndSlotReuse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source")
        let legacyFile = sourceRoot.appendingPathComponent("docs/legacy.md")
        let addedFile = sourceRoot.appendingPathComponent("docs/new.md")
        try FileManager.default.createDirectory(at: legacyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("owner baseline".utf8).write(to: legacyFile)
        try Data("new owner file".utf8).write(to: addedFile)

        let legacySelection = try CorpusSelection(folders: [], documents: ["docs/legacy.md"])
        let expandedSelection = try CorpusSelection(folders: [], documents: ["docs/legacy.md", "docs/new.md"])
        let projectID = UUID()
        let legacyDescriptor = SharedProjectDescriptor(id: projectID, name: "Legacy source",
            scope: try CorpusScope(folder: ""), selection: legacySelection)
        let expandedDescriptor = SharedProjectDescriptor(id: projectID, name: "Legacy source",
            scope: try CorpusScope(folder: ""), selection: expandedSelection)
        let reader = ProjectCorpusReader()
        let legacySource = SharedProjectSource(descriptor: legacyDescriptor, rootURL: sourceRoot) {
            try await reader.snapshot(root: sourceRoot, selection: legacySelection)
        }
        let expandedSource = SharedProjectSource(descriptor: expandedDescriptor, rootURL: sourceRoot) {
            try await reader.snapshot(root: sourceRoot, selection: expandedSelection)
        }
        let serverRoot = root.appendingPathComponent("Server")
        let runtime = DesktopDirectRuntime(root: serverRoot, credentials: PeerMemoryCredentials(), now: { Date() })
        var running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [legacySource])
        var phase = "enroll and import legacy project"
        do {
            let connectionStore = FileDesktopPeerConnectionStore(root: root.appendingPathComponent("Connections"))
            let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
            let workspaceRoot = root.appendingPathComponent("Working")
            let outbox = FileDesktopPeerOutboxStore(root: root.appendingPathComponent("Outbox"))
            let intentsRoot = root.appendingPathComponent("ReceiptIntents")
            let credentials = PeerMemoryCredentials()
            let revoker = PeerRevokerFixture()
            let library = DesktopPeerLibrary(connections: connectionStore, copies: copies,
                workspace: DesktopPeerWorkspace(root: workspaceRoot, copies: copies), credentials: credentials,
                remote: DesktopPeerHTTPSRemote(), revoker: revoker, outbox: outbox,
                receiptApplier: DesktopPeerReceiptApplier(workingRoot: workspaceRoot, copies: copies,
                    intents: FileDesktopPeerReceiptIntentStore(root: intentsRoot)))
            let connection = try await library.enroll(endpoint: running.endpoint, fingerprint: nil,
                invitation: nil, name: "Updating Mac")
            let registry = try await runtime.consentState()
            let request = try XCTUnwrap(registry.requests.first)
            try await runtime.approve(requestID: request.id, code: request.comparisonCode, projectIDs: [projectID])
            let copy = try await library.importProject(connectionID: connection.id, projectID: projectID)
            let directory = try await library.open(copyID: copy.id)
            try Data("queued proposal".utf8).write(to: directory.appendingPathComponent("docs/legacy.md"))
            let sendResult = try await library.send(copyID: copy.id, buffers: [])
            let firstID = try XCTUnwrap(sendResult)
            let queuedResult = try await library.pendingProposal(copyID: copy.id)
            let queued = try XCTUnwrap(queuedResult)
            XCTAssertEqual(queued.proposal.id, firstID)

            // Convert the just-staged manifest to the prior schema, which stored only selection.
            let stage = serverRoot.appendingPathComponent("Proposals")
                .appendingPathComponent(connection.remoteDeviceID.uuidString).appendingPathComponent(projectID.uuidString)
            let manifestURL = stage.appendingPathComponent("manifest.json")
            let encodedManifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
            let encodedSelection = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacySelection))
            let legacyManifest: [String: Any] = [
                "deviceID": connection.remoteDeviceID.uuidString,
                "upload": try XCTUnwrap(encodedManifest["upload"]),
                "selection": encodedSelection
            ]
            try JSONSerialization.data(withJSONObject: legacyManifest, options: [.sortedKeys]).write(to: manifestURL)

            let serverPort = UInt16(try XCTUnwrap(running.endpoint.port))
            phase = "restart owner with expanded grant"
            try await runtime.stop()
            running = try await runtime.start(host: "127.0.0.1", port: serverPort, projects: [expandedSource])

            phase = "retry the pinned proposal under the expanded grant"
            let retriedID = try await library.send(copyID: copy.id, buffers: [])
            XCTAssertEqual(retriedID, firstID, "A compatible grant expansion must retry the immutable proposal")
            let visibleCopies = try await library.copies()
            XCTAssertEqual(visibleCopies.map(\.id), [copy.id], "A broader grant keeps the existing narrower copy visible")
            let retainedOutbox = try await outbox.load(copyID: copy.id)
            XCTAssertEqual(retainedOutbox?.proposal, queued.proposal)
            let incomingValues = try await runtime.incomingProposals()
            let incoming = try XCTUnwrap(incomingValues.first)
            XCTAssertEqual(incoming.view?.selection, legacySelection)
            let proposal = try await runtime.incomingProposal(deviceID: incoming.deviceID, upload: incoming.upload)
            XCTAssertEqual(proposal, queued.proposal)
            phase = "review pinned proposal at owner"
            let review = try await runtime.reviewIncomingProposal(deviceID: incoming.deviceID, upload: incoming.upload)
            XCTAssertEqual(review.source.files.map(\.path), ["docs/legacy.md"],
                           "Owner review remains bounded by the pre-expansion proposal selection")
            let ownerDisk = try await reader.snapshot(root: sourceRoot, selection: legacySelection)
            let accepted = try await runtime.applyIncomingProposal(deviceID: incoming.deviceID, upload: incoming.upload,
                review: review, decisions: ["docs/legacy.md": .local], projectRoot: sourceRoot,
                currentSource: review.source, currentDisk: ownerDisk)
            XCTAssertEqual(accepted.receipt.accepted.files.map(\.path), ["docs/legacy.md"])
            XCTAssertEqual(try Data(contentsOf: legacyFile), Data("queued proposal".utf8))
            XCTAssertEqual(try Data(contentsOf: addedFile), Data("new owner file".utf8))

            // Restart both sides before retrieving and acknowledging the accepted receipt.
            phase = "restart owner and retrieve accepted receipt"
            try await runtime.stop()
            running = try await runtime.start(host: "127.0.0.1", port: serverPort, projects: [expandedSource])
            let reopened = DesktopPeerLibrary(connections: connectionStore, copies: copies,
                workspace: DesktopPeerWorkspace(root: workspaceRoot, copies: copies), credentials: credentials,
                remote: DesktopPeerHTTPSRemote(), revoker: revoker, outbox: outbox,
                receiptApplier: DesktopPeerReceiptApplier(workingRoot: workspaceRoot, copies: copies,
                    intents: FileDesktopPeerReceiptIntentStore(root: intentsRoot)))
            let receiptValue = try await reopened.pendingReceipt(copyID: copy.id)
            let receipt = try XCTUnwrap(receiptValue)
            XCTAssertEqual(receipt, accepted.receipt)
            phase = "apply and acknowledge accepted receipt"
            _ = try await reopened.acknowledge(copyID: copy.id, receipt: receipt, buffers: [])
            let clearedOutbox = try await outbox.load(copyID: copy.id)
            XCTAssertNil(clearedOutbox)

            let proposalClient = try DesktopPeerProposalClient(endpoint: running.endpoint,
                certificateFingerprint: running.certificateFingerprint)
            let secretValue = try await credentials.credential(deviceID: connection.id)
            let secret = try XCTUnwrap(secretValue)
            phase = "repeat receipt acknowledgment"
            try await proposalClient.acknowledge(queued.proposal, receipt: receipt,
                deviceID: connection.remoteDeviceID, credential: secret)
            try await proposalClient.acknowledge(queued.proposal, receipt: receipt,
                deviceID: connection.remoteDeviceID, credential: secret)
            let nextProposal = try DesktopPeerProposal(projectID: projectID, selection: legacySelection,
                base: receipt.accepted, proposed: CorpusSnapshot(revision: "next", files: [
                    CorpusFile(path: "docs/legacy.md", content: Data("next proposal".utf8))
                ]))
            phase = "reuse acknowledged proposal slot"
            try await proposalClient.submit(nextProposal, deviceID: connection.remoteDeviceID,
                credential: secret)
            let nextIncoming = try await runtime.incomingProposals()
            XCTAssertEqual(nextIncoming.map(\.upload.proposalID), [nextProposal.id],
                           "The acknowledged staging slot must accept the next proposal")
            try await runtime.stop()
        } catch {
            try? await runtime.stop()
            throw NSError(domain: "DesktopPeerLibraryTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Legacy grant expansion scenario failed during \(phase): \(error)"])
        }
    }

    func testRealPinnedHTTPSEnrollmentImportAndRevocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Actual TLS notes", scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: ["docs"], documents: []))
        let files = [CorpusFile(path: "docs/note.md", content: Data("real TLS corpus".utf8))]
        let source = SharedProjectSource(descriptor: descriptor) {
            CorpusSnapshot(revision: CorpusRevision.make(files: files), files: files)
        }
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Server"), credentials: PeerMemoryCredentials(), now: { Date() })
        let running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [source])
        do {
            let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
            let workspace = DesktopPeerWorkspace(root: root.appendingPathComponent("Working"), copies: copies)
            let revoker = PeerRevokerFixture()
            let library = DesktopPeerLibrary(connections: FileDesktopPeerConnectionStore(root: root.appendingPathComponent("Connections")),
                copies: copies, workspace: workspace, credentials: PeerMemoryCredentials(), remote: DesktopPeerHTTPSRemote(), revoker: revoker,
                outbox: FileDesktopPeerOutboxStore(root: root.appendingPathComponent("Outbox")))
            let connection = try await library.enroll(endpoint: running.endpoint, fingerprint: nil, invitation: nil, name: "MacBook QA")
            let registry = try await runtime.consentState()
            let request = try XCTUnwrap(registry.requests.first)
            XCTAssertEqual(request.kind, .desktopPeer)
            XCTAssertEqual(connection.comparisonCode, request.comparisonCode)
            XCTAssertEqual(connection.remoteDeviceID, request.id)
            try await runtime.approve(requestID: request.id, code: request.comparisonCode, projectIDs: [descriptor.id])
            let approved = try await runtime.consentState()
            XCTAssertEqual(approved.devices.first?.kind, .desktopPeer)
            let copy = try await library.importProject(connectionID: connection.id, projectID: descriptor.id)
            let directory = try await library.open(copyID: copy.id)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/note.md")), Data("real TLS corpus".utf8))
            try Data("sent over TLS".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
            let sentID = try await library.send(copyID: copy.id, buffers: [])
            let intent = try await library.pendingProposal(copyID: copy.id)
            XCTAssertEqual(sentID, intent?.proposal.id)
            let inbox = try await runtime.incomingProposals()
            XCTAssertEqual(inbox.first?.upload.proposalID, sentID)
            let received = try await runtime.incomingProposal(deviceID: request.id, upload: XCTUnwrap(inbox.first?.upload))
            XCTAssertEqual(received, intent?.proposal)
            try Data("later native edit".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
            let retried = try await library.send(copyID: copy.id, buffers: [])
            XCTAssertEqual(retried, sentID)
            let later = try await copies.load(id: copy.id)
            XCTAssertEqual(later?.files.first?.content, Data("later native edit".utf8))
            XCTAssertEqual(later?.base, copy.base)
            try await runtime.revoke(deviceID: request.id)
            let status = try await library.refresh(connectionID: connection.id)
            XCTAssertEqual(status.access, .revoked)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Outbox").appendingPathComponent(copy.id.uuidString).appendingPathExtension("json").path))
            let closed = await revoker.closedIDs
            XCTAssertTrue(closed.contains(copy.id))
            do { _ = try await library.open(copyID: copy.id); XCTFail("Revoked TLS copy reopened") } catch {}
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }

    func testFailedSendPersistsCaptureAndReopenedRetryPreservesLaterEditsUntilReceipt() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        let copy = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        let directory = try await fixture.library.open(copyID: copy.id)
        let clean = try await fixture.library.send(copyID: copy.id, buffers: [])
        XCTAssertNil(clean)
        let noIntent = try await fixture.outbox.load(copyID: copy.id)
        XCTAssertNil(noIntent)
        try Data("first capture".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
        await fixture.remote.setReachable(false)
        do { _ = try await fixture.library.send(copyID: copy.id, buffers: []); XCTFail("Offline send succeeded") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        let loadedIntent = try await fixture.library.pendingProposal(copyID: copy.id)
        let intent = try XCTUnwrap(loadedIntent)
        XCTAssertEqual(intent.proposal.proposed.files.first?.content, Data("first capture".utf8))
        try Data("later disk edit".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
        try Data("later addition".utf8).write(to: directory.appendingPathComponent("docs/new.md"))
        await fixture.remote.setReachable(true)
        let reopened = DesktopPeerLibrary(connections: fixture.connections, copies: fixture.copies, workspace: fixture.workspace,
            credentials: fixture.credentials, remote: fixture.remote, revoker: PeerRevokerFixture(), outbox: fixture.outbox)
        let retry = try await reopened.send(copyID: copy.id, buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "active later draft")])
        XCTAssertEqual(retry, intent.proposal.id)
        let publications = await fixture.remote.publications
        XCTAssertEqual(publications, [intent.proposal])
        let loadedCopy = try await fixture.copies.load(id: copy.id)
        let current = try XCTUnwrap(loadedCopy)
        XCTAssertEqual(current.base, copy.base)
        XCTAssertEqual(current.files.first { $0.path == "docs/note.md" }?.content, Data("active later draft".utf8))
        XCTAssertEqual(current.files.first { $0.path == "docs/new.md" }?.content, Data("later addition".utf8))
        let retained = try await reopened.pendingProposal(copyID: copy.id)
        XCTAssertEqual(retained, intent)
        await fixture.remote.setAccess(.revoked)
        do { _ = try await reopened.send(copyID: copy.id, buffers: []); XCTFail("Revoked copy sent") } catch {}
        let cleared = try await fixture.outbox.load(copyID: copy.id)
        XCTAssertNil(cleared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testApprovedImportOpensOfflineAndCapturesNativeEditsForManualComparison() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        let pending = try await fixture.library.refresh(connectionID: connection.id)
        XCTAssertEqual(pending.access, .pending)
        await fixture.remote.setAccess(.authorized)
        let copy = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        let directory = try await fixture.library.open(copyID: copy.id)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/note.md")), Data("remote".utf8))
        try Data("offline edit".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
        await fixture.remote.setReachable(false)
        let offline = try await fixture.library.open(copyID: copy.id)
        XCTAssertEqual(try Data(contentsOf: offline.appendingPathComponent("docs/note.md")), Data("offline edit".utf8))
        do { _ = try await fixture.library.compare(copyID: copy.id, buffers: []); XCTFail("Offline remote comparison succeeded") } catch {}
        let captured = try await fixture.copies.load(id: copy.id)
        XCTAssertEqual(captured?.base, copy.base)
        XCTAssertEqual(captured?.files.first?.content, Data("offline edit".utf8))
        await fixture.remote.setReachable(true)
        let comparison = try await fixture.library.compare(copyID: copy.id, buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "active draft")])
        XCTAssertEqual(comparison.comparison.differences.map(\.path), ["docs/note.md"])
        XCTAssertEqual(comparison.copy.files.first?.content, Data("active draft".utf8))
        XCTAssertEqual(comparison.remote.files.first?.content, Data("remote".utf8))
        let secret = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNotNil(secret)
        let wrongAccount = try await fixture.credentials.credential(deviceID: connection.remoteDeviceID)
        XCTAssertNil(wrongAccount)
        let metadata = try String(contentsOf: fixture.connectionRoot.appendingPathComponent(connection.id.uuidString).appendingPathExtension("json"), encoding: .utf8)
        XCTAssertFalse(metadata.contains(try XCTUnwrap(secret)))
        let repeated = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        XCTAssertEqual(repeated.id, copy.id)
        let transfers = await fixture.remote.snapshotCount
        XCTAssertEqual(transfers, 2) // Import and explicit comparison; reopening/import retry does not redownload.
    }

    func testRevocationBeforeSelectedProjectImportReturnsRevokedErrorAndCleansCopy() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        let selectedProjects = try await fixture.library.refresh(connectionID: connection.id)
        XCTAssertEqual(selectedProjects.projects.map(\.id), [fixture.remote.project.id])
        let existingCopy = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        let directory = try await fixture.library.open(copyID: existingCopy.id)

        // The user selected this project while authorized; its grant is withdrawn before import is retried.
        await fixture.remote.setAccess(.revoked)
        do {
            _ = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
            XCTFail("A withdrawn grant must not complete the selected import")
        } catch {
            XCTAssertEqual(error as? SyncError, .revoked)
        }

        let deniedConnection = try await fixture.connections.load(id: connection.id)
        XCTAssertTrue(try XCTUnwrap(deniedConnection).revoked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let removedCopy = try await fixture.copies.load(id: existingCopy.id)
        XCTAssertNil(removedCopy)
        let removedCredential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNil(removedCredential)
        let closedCopies = await fixture.revoker.closedIDs
        XCTAssertTrue(closedCopies.contains(existingCopy.id))
    }

    func testConfirmedRevocationSurvivesConnectionStoreSaveFailure() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil,
            invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        _ = try await fixture.library.refresh(connectionID: connection.id)
        let copy = try await fixture.library.importProject(connectionID: connection.id,
            projectID: fixture.remote.project.id)
        let copyDirectory = try await fixture.library.open(copyID: copy.id)

        let failingStore = FailingPeerConnectionStore(base: fixture.connections)
        let library = DesktopPeerLibrary(connections: failingStore, copies: fixture.copies,
            workspace: fixture.workspace, credentials: fixture.credentials, remote: fixture.remote,
            revoker: fixture.revoker, outbox: fixture.outbox)
        await failingStore.failNextSave()
        await fixture.remote.setAccess(.revoked)
        do {
            _ = try await library.refresh(connectionID: connection.id)
            XCTFail("The injected metadata-store failure must be reported")
        } catch {
            XCTAssertEqual(error as? PeerConnectionStoreWriteFailure, .injected)
        }

        let storedBeforeRecovery = try await fixture.connections.load(id: connection.id)
        XCTAssertFalse(try XCTUnwrap(storedBeforeRecovery).revoked,
                       "The failure leaves the previous connection snapshot on disk")
        let removedCredential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNil(removedCredential,
                     "Credential removal is the durable denial witness when the connection write fails")
        let deniedReaderProjects = await fixture.revoker.readerDeniedProjects(for: connection.id)
        XCTAssertEqual(deniedReaderProjects, Set([fixture.remote.project.id]))

        let restarted = DesktopPeerLibrary(connections: fixture.connections, copies: fixture.copies,
            workspace: fixture.workspace, credentials: fixture.credentials, remote: fixture.remote,
            revoker: fixture.revoker, outbox: fixture.outbox)
        let recovered = try await restarted.connections()
        XCTAssertTrue(try XCTUnwrap(recovered.first).revoked,
                      "A new library instance must recover denial from the missing credential")
        let recoveredCopies = try await restarted.copies()
        XCTAssertTrue(recoveredCopies.isEmpty,
                      "The old grant must not expose its managed copy while metadata cleanup is pending")
        let recoveredStatus = try await restarted.refresh(connectionID: connection.id)
        XCTAssertEqual(recoveredStatus.access, .revoked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyDirectory.path),
                       "A later cleanup pass removes the copy after restoring the revoked state")
    }

    func testPendingRemovedAndNarrowedProjectsAreDeniedBeforeGrantSaveFailure() async throws {
        for transition in PeerGrantFailureTransition.allCases {
            let fixture = try PeerLibraryFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil,
                invitation: nil, name: "MacBook")
            await fixture.remote.setAccess(.authorized)
            _ = try await fixture.library.refresh(connectionID: connection.id)
            let copy = try await fixture.library.importProject(connectionID: connection.id,
                projectID: fixture.remote.project.id)
            let workspace = try await fixture.library.open(copyID: copy.id)
            let localFile = workspace.appendingPathComponent("docs/note.md")
            try Data("local draft".utf8).write(to: localFile)
            _ = try await fixture.library.send(copyID: copy.id, buffers: [])
            let authorized = try await fixture.connections.load(id: connection.id)
            let previousGrant = try XCTUnwrap(authorized).grants[fixture.remote.project.id]

            let failingStore = FailingPeerConnectionStore(base: fixture.connections)
            let library = DesktopPeerLibrary(connections: failingStore, copies: fixture.copies,
                workspace: fixture.workspace, credentials: fixture.credentials, remote: fixture.remote,
                revoker: fixture.revoker, outbox: fixture.outbox)
            await failingStore.failNextSave()
            switch transition {
            case .pending:
                await fixture.remote.setAccess(.pending)
            case .removed:
                await fixture.remote.withdrawProject()
            case .narrowed:
                let narrowed = SharedProjectDescriptor(id: fixture.remote.project.id,
                    name: fixture.remote.project.name, scope: fixture.remote.project.scope,
                    selection: try CorpusSelection(folders: [], documents: ["docs/other.md"]))
                await fixture.remote.replaceProject(narrowed)
            }

            do {
                _ = try await library.refresh(connectionID: connection.id)
                XCTFail("The injected grant-store failure must be reported for \(transition)")
            } catch {
                XCTAssertEqual(error as? PeerConnectionStoreWriteFailure, .injected)
            }

            let persisted = try await fixture.connections.load(id: connection.id)
            XCTAssertEqual(try XCTUnwrap(persisted).grants[fixture.remote.project.id],
                           previousGrant,
                           "The original authorization snapshot remains on disk for \(transition)")
            let deniedProjects = await fixture.revoker.readerDeniedProjects(for: connection.id)
            XCTAssertEqual(deniedProjects, [fixture.remote.project.id],
                           "Reader caches are denied before the failed connection write for \(transition)")
            let authorizationRequired = await fixture.revoker.authorizationRequired(
                connectionID: connection.id, projectID: fixture.remote.project.id)
            XCTAssertTrue(authorizationRequired,
                          "The durable project barrier must protect editable copies for \(transition)")
            XCTAssertEqual(try Data(contentsOf: localFile), Data("local draft".utf8),
                           "A failed connection save must not discard local edits for \(transition)")
            let immediateCopies = try await library.copies()
            XCTAssertFalse(immediateCopies.contains { $0.id == copy.id },
                           "A denied editable copy must disappear from the live list for \(transition)")
            do {
                _ = try await library.open(copyID: copy.id)
                XCTFail("A denied editable copy must not reopen for \(transition)")
            } catch {
                XCTAssertEqual(error as? DesktopPeerLibraryError, .unauthorizedProject)
            }

            let persistedBarrier = await fixture.revoker.authorizationBarrierStore()
            let restartedRevoker = PeerRevokerFixture(authorizationBarrier: persistedBarrier)
            let restarted = DesktopPeerLibrary(connections: fixture.connections, copies: fixture.copies,
                workspace: fixture.workspace, credentials: fixture.credentials, remote: fixture.remote,
                revoker: restartedRevoker, outbox: fixture.outbox)
            let restartedCopies = try await restarted.copies()
            XCTAssertFalse(restartedCopies.contains { $0.id == copy.id },
                           "A restarted library must continue hiding the denied copy for \(transition)")
            do {
                _ = try await restarted.open(copyID: copy.id)
                XCTFail("A restarted library must not reopen a denied copy for \(transition)")
            } catch {
                XCTAssertEqual(error as? DesktopPeerLibraryError, .unauthorizedProject)
            }
            XCTAssertEqual(try Data(contentsOf: localFile), Data("local draft".utf8),
                           "The workspace remains intact after library recreation for \(transition)")
        }
    }

    func testProjectGrantChangesBlockRemoteCopyAndPreserveLocalEdits() async throws {
        for transition in PeerGrantFailureTransition.allCases {
            let fixture = try PeerLibraryFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil,
                invitation: nil, name: "MacBook")
            await fixture.remote.setAccess(.authorized)
            _ = try await fixture.library.refresh(connectionID: connection.id)
            let copy = try await fixture.library.importProject(connectionID: connection.id,
                projectID: fixture.remote.project.id)
            let workspace = try await fixture.library.open(copyID: copy.id)
            let localFile = workspace.appendingPathComponent("docs/note.md")
            try Data("local draft".utf8).write(to: localFile)
            _ = try await fixture.library.send(copyID: copy.id, buffers: [])

            switch transition {
            case .pending:
                await fixture.remote.setAccess(.pending)
            case .removed:
                await fixture.remote.withdrawProject()
            case .narrowed:
                let narrowed = SharedProjectDescriptor(id: fixture.remote.project.id,
                    name: fixture.remote.project.name, scope: fixture.remote.project.scope,
                    selection: try CorpusSelection(folders: [], documents: ["docs/other.md"]))
                await fixture.remote.replaceProject(narrowed)
            }

            _ = try await fixture.library.refresh(connectionID: connection.id)
            let stored = try await fixture.connections.load(id: connection.id)
            XCTAssertEqual(try XCTUnwrap(stored).copies[copy.remoteProjectID], copy.id,
                           "Project-level status changes retain the editable-copy identity for \(transition)")
            let retainedCopy = try await fixture.copies.load(id: copy.id)
            XCTAssertNotNil(retainedCopy,
                            "The local copy archive remains available for a later authorized retry")
            XCTAssertEqual(try Data(contentsOf: localFile), Data("local draft".utf8),
                           "A project-level status change must preserve local disk edits for \(transition)")
            let closedIDs = await fixture.revoker.closedIDs
            XCTAssertFalse(closedIDs.contains(copy.id),
                           "Project-level denial must not force-close a local editor with unsaved changes")
            let retainedProposal = try await fixture.outbox.load(copyID: copy.id)
            XCTAssertNil(retainedProposal,
                         "A stale proposal must not replay after authorization is restored")

            let hiddenWhileBarriered = try await fixture.library.copies()
            XCTAssertFalse(hiddenWhileBarriered.contains { $0.id == copy.id },
                           "The project barrier hides the copy after successful STATUS for \(transition)")
            do {
                _ = try await fixture.library.open(copyID: copy.id)
                XCTFail("The project barrier must block new access for \(transition)")
            } catch {
                let expected: DesktopPeerLibraryError = transition == .narrowed
                    ? .selectionChanged : .unauthorizedProject
                XCTAssertEqual(error as? DesktopPeerLibraryError, expected)
            }

            await fixture.revoker.clearAuthorizationRequirement(connectionID: connection.id,
                                                                 projectIDs: [copy.remoteProjectID])
            let stillHidden = try await fixture.library.copies()
            XCTAssertFalse(stillHidden.contains { $0.id == copy.id },
                           "Withdrawn or narrowed grants cannot expose an out-of-scope copy after barrier clear")
            if transition == .narrowed {
                do {
                    _ = try await fixture.library.open(copyID: copy.id)
                    XCTFail("An older, broader copy must stay unavailable under the narrowed grant")
                } catch {
                    XCTAssertEqual(error as? DesktopPeerLibraryError, .selectionChanged)
                }
            }
            XCTAssertEqual(try Data(contentsOf: localFile), Data("local draft".utf8),
                           "Blocking remote access still preserves local edits")

            await fixture.remote.setAccess(.authorized)
            if transition == .removed { await fixture.remote.restoreProject() }
            if transition == .narrowed { await fixture.remote.replaceProject(fixture.remote.project) }
            _ = try await fixture.library.refresh(connectionID: connection.id)
            await fixture.revoker.clearAuthorizationRequirement(connectionID: connection.id,
                                                                 projectIDs: [copy.remoteProjectID])
            let restored = try await fixture.library.copies()
            XCTAssertTrue(restored.contains { $0.id == copy.id },
                          "A matching grant restores the retained copy after authenticated reconciliation")
            let reopened = try await fixture.library.open(copyID: copy.id)
            XCTAssertEqual(try Data(contentsOf: reopened.appendingPathComponent("docs/note.md")),
                           Data("local draft".utf8))
        }
    }

    func testMissingProjectGrantRemainsDistinctFromRevokedDevice() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        let unsharedProjectID = UUID()

        do {
            _ = try await fixture.library.importProject(connectionID: connection.id, projectID: unsharedProjectID)
            XCTFail("An unshared project must not be imported")
        } catch {
            XCTAssertEqual(error as? DesktopPeerLibraryError, .unauthorizedProject)
        }

        let stillAuthorized = try await fixture.connections.load(id: connection.id)
        XCTAssertFalse(try XCTUnwrap(stillAuthorized).revoked)
    }

    func testDeviceRevocationBetweenCataloguePreflightAndRequestCleansCopy() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        let copy = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        let directory = try await fixture.library.open(copyID: copy.id)
        await fixture.remote.setNextCatalogueMutation(.revokeDevice)

        do {
            _ = try await fixture.library.catalogue(connectionID: connection.id, projectID: fixture.remote.project.id)
            XCTFail("A revoked device must not receive the catalogue")
        } catch {
            XCTAssertEqual(error as? SyncError, .revoked)
        }

        let revoked = try await fixture.connections.load(id: connection.id)
        XCTAssertTrue(try XCTUnwrap(revoked).revoked)
        let removedCopy = try await fixture.copies.load(id: copy.id)
        let removedCredential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNil(removedCopy)
        XCTAssertNil(removedCredential)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let closedCopies = await fixture.revoker.closedIDs
        XCTAssertTrue(closedCopies.contains(copy.id))
    }

    func testDeviceRevocationBetweenComparePreflightAndSnapshotCleansCopy() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        let copy = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        let directory = try await fixture.library.open(copyID: copy.id)
        await fixture.remote.setNextSnapshotMutation(.revokeDevice)

        do {
            _ = try await fixture.library.compare(copyID: copy.id, buffers: [])
            XCTFail("A revoked device must not complete a comparison snapshot")
        } catch {
            XCTAssertEqual(error as? SyncError, .revoked)
        }

        let revoked = try await fixture.connections.load(id: connection.id)
        XCTAssertTrue(try XCTUnwrap(revoked).revoked)
        let removedCopy = try await fixture.copies.load(id: copy.id)
        let removedCredential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNil(removedCopy)
        XCTAssertNil(removedCredential)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let closedCopies = await fixture.revoker.closedIDs
        XCTAssertTrue(closedCopies.contains(copy.id))
    }

    func testProjectGrantWithdrawalBetweenPreflightAndSnapshotRemainsProjectScoped() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        await fixture.remote.setNextSnapshotMutation(.withdrawProject)

        do {
            _ = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
            XCTFail("A withdrawn project must not complete the snapshot request")
        } catch {
            XCTAssertEqual(error as? DesktopPeerLibraryError, .unauthorizedProject)
        }

        let updated = try await fixture.connections.load(id: connection.id)
        XCTAssertFalse(try XCTUnwrap(updated).revoked)
        XCTAssertTrue(try XCTUnwrap(updated).grants.isEmpty)
        let retainedCredential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNotNil(retainedCredential)
        XCTAssertTrue(try XCTUnwrap(updated).copies.isEmpty)
        let deniedProjectCaches = await fixture.revoker.readerDeniedProjects(for: connection.id)
        XCTAssertEqual(deniedProjectCaches, [fixture.remote.project.id])
    }

    func testProjectGrantWithdrawalBetweenFilePreflightAndReadRemainsProjectScoped() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        await fixture.remote.setNextFileMutation(.withdrawProject)
        let entry = RemoteFileEntry(file: CorpusFile(path: "docs/note.md", content: Data("remote".utf8)))

        do {
            _ = try await fixture.library.file(connectionID: connection.id, projectID: fixture.remote.project.id, entry: entry)
            XCTFail("A withdrawn project must not complete the file request")
        } catch {
            XCTAssertEqual(error as? DesktopPeerLibraryError, .unauthorizedProject)
        }

        let updated = try await fixture.connections.load(id: connection.id)
        XCTAssertFalse(try XCTUnwrap(updated).revoked)
        XCTAssertTrue(try XCTUnwrap(updated).grants.isEmpty)
        let retainedCredential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNotNil(retainedCredential)
        let deniedProjectCaches = await fixture.revoker.readerDeniedProjects(for: connection.id)
        XCTAssertEqual(deniedProjectCaches, [fixture.remote.project.id])
    }

    func testFileRemovedFromSelectionBetweenPreflightAndReadIsReportedOutsideScope() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        await fixture.remote.setNextFileMutation(.narrowSelection)
        let entry = RemoteFileEntry(file: CorpusFile(path: "docs/note.md", content: Data("remote".utf8)))

        do {
            _ = try await fixture.library.file(connectionID: connection.id, projectID: fixture.remote.project.id, entry: entry)
            XCTFail("A file removed from the current selection must not receive a stale fallback")
        } catch {
            XCTAssertEqual(error as? SyncError, .outsideScope)
        }

        let updated = try await fixture.connections.load(id: connection.id)
        XCTAssertFalse(try XCTUnwrap(updated).revoked, "A narrowed file selection must not revoke the device")
        XCTAssertEqual(try XCTUnwrap(updated).grants[fixture.remote.project.id],
                       try CorpusSelection(folders: [], documents: ["docs/other.md"]))
        let retainedCredential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNotNil(retainedCredential)
        let deniedReaderProjects = await fixture.revoker.readerDeniedProjects(for: connection.id)
        XCTAssertEqual(deniedReaderProjects, [fixture.remote.project.id],
                       "A narrowed file grant invalidates any reader cache from its previous selection")
    }

    func testUnresolvedCatalogueForbiddenResponseIsPreservedWhenProjectStillAppearsAuthorized() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        await fixture.remote.setNextCatalogueMutation(.denyRequest)

        do {
            _ = try await fixture.library.catalogue(connectionID: connection.id, projectID: fixture.remote.project.id)
            XCTFail("An unexplained forbidden response must remain an access denial")
        } catch {
            XCTAssertEqual(error as? SyncError, .httpAccessDenied(operation: .catalogue, status: 403))
        }

        let stillAuthorized = try await fixture.connections.load(id: connection.id)
        XCTAssertFalse(try XCTUnwrap(stillAuthorized).revoked)
        let retainedCredential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNotNil(retainedCredential)
    }

    func testRevocationIsDurableBeforeFailedPurgeAndRetriesWithoutNetworkOrCredential() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        let copy = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        let directory = try await fixture.library.open(copyID: copy.id)
        await fixture.workspace.setFailRemoval(true)
        await fixture.remote.setAccess(.revoked)
        do { _ = try await fixture.library.refresh(connectionID: connection.id); XCTFail("Failed purge confirmed") } catch {}
        let denied = try await fixture.connections.load(id: connection.id)
        XCTAssertEqual(denied?.revoked, true)
        XCTAssertEqual(denied?.copies[copy.remoteProjectID], copy.id)
        let hidden = try await fixture.library.copies()
        XCTAssertTrue(hidden.isEmpty)
        do { _ = try await fixture.library.open(copyID: copy.id); XCTFail("Revoked copy reopened") }
        catch { XCTAssertEqual(error as? SyncError, .revoked) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        await fixture.workspace.setFailRemoval(false)
        await fixture.remote.setReachable(false)
        let retried = try await fixture.library.refresh(connectionID: connection.id)
        XCTAssertEqual(retried.access, .revoked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let removed = try await fixture.copies.load(id: copy.id)
        XCTAssertNil(removed)
        let credential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNil(credential)
        let completed = try await fixture.connections.load(id: connection.id)
        XCTAssertTrue(try XCTUnwrap(completed).copies.isEmpty)
        XCTAssertTrue(try XCTUnwrap(completed).revoked)
        let deniedReaderProjects = await fixture.revoker.readerDeniedProjects(for: connection.id)
        XCTAssertEqual(deniedReaderProjects, [fixture.remote.project.id],
                       "Reader caches must be denied before the fallible workspace purge")
    }

    func testDeferredLegacyPeerDoesNotBlockHealthyPeerOrNewEnrollment() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let legacy = try await fixture.library.enroll(
            endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "Legacy")
        await fixture.remote.setAccess(.authorized)
        _ = try await fixture.library.refresh(connectionID: legacy.id)
        await fixture.credentials.deferRead(id: legacy.id)

        let fresh = try await fixture.library.enroll(
            endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "New")
        let listed = try await fixture.library.connections()
        let deferred = try XCTUnwrap(listed.first { $0.id == legacy.id })
        XCTAssertTrue(deferred.credentialDeferred)
        XCTAssertFalse(deferred.revoked)
        XCTAssertFalse(deferred.grants.isEmpty)
        XCTAssertEqual(listed.filter { !$0.credentialDeferred }.map(\.id), [fresh.id])
        let healthy = try await fixture.library.refresh(connectionID: fresh.id)
        XCTAssertEqual(healthy.access, .authorized)
        let durable = try await fixture.connections.load(id: legacy.id)
        XCTAssertFalse(try XCTUnwrap(durable).credentialDeferred)

        do {
            _ = try await fixture.library.refresh(connectionID: legacy.id)
            XCTFail("Deferred peer must not reach the remote")
        } catch DesktopPeerCredentialError.legacyAuthorizationUnavailable {}
        await fixture.credentials.deferRead(id: nil)
        let recovered = try await fixture.library.refresh(connectionID: legacy.id)
        XCTAssertEqual(recovered.access, .authorized)
    }

    func testServerDeviceIDReuseCannotReplaceAnotherConnectionsCredentialAccount() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "One")
        let second = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "Two")
        XCTAssertEqual(first.remoteDeviceID, second.remoteDeviceID)
        XCTAssertNotEqual(first.id, second.id)
        let firstSecret = try await fixture.credentials.credential(deviceID: first.id)
        let secondSecret = try await fixture.credentials.credential(deviceID: second.id)
        XCTAssertNotNil(firstSecret); XCTAssertNotNil(secondSecret)
        XCTAssertNotEqual(firstSecret, secondSecret)
        let connections = try await fixture.library.connections()
        XCTAssertEqual(connections.count, 2)
    }
}

private struct PeerLibraryFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let endpoint = URL(string: "https://127.0.0.1:40882")!
    let connectionRoot: URL
    let connections: FileDesktopPeerConnectionStore
    let copies: FileDesktopPeerCopyStore
    let workspace: PeerWorkspaceProxy
    let credentials = PeerMemoryCredentials()
    let remote: PeerRemoteFixture
    let revoker: PeerRevokerFixture
    let outbox: FileDesktopPeerOutboxStore
    let library: DesktopPeerLibrary
    init() throws {
        connectionRoot = root.appendingPathComponent("Connections")
        connections = FileDesktopPeerConnectionStore(root: connectionRoot)
        copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
        workspace = PeerWorkspaceProxy(DesktopPeerWorkspace(root: root.appendingPathComponent("Working"), copies: copies))
        remote = try PeerRemoteFixture()
        outbox = FileDesktopPeerOutboxStore(root: root.appendingPathComponent("Outbox"))
        revoker = PeerRevokerFixture()
        library = DesktopPeerLibrary(connections: connections, copies: copies, workspace: workspace,
            credentials: credentials, remote: remote, revoker: revoker, outbox: outbox, now: { Date(timeIntervalSince1970: 1_000) })
    }
}

private actor PeerRevokerFixture: DesktopPeerAccessRevoker {
    private(set) var closedIDs: Set<UUID> = []
    private var deniedReaderProjects: [UUID: Set<UUID>] = [:]
    private let authorizationBarrier: PeerAuthorizationBarrierFixture
    init(authorizationBarrier: PeerAuthorizationBarrierFixture = PeerAuthorizationBarrierFixture()) {
        self.authorizationBarrier = authorizationBarrier
    }
    func denyReaderCaches(connectionID: UUID, projectIDs: [UUID]) async {
        deniedReaderProjects[connectionID, default: []].formUnion(projectIDs)
        await authorizationBarrier.require(connectionID: connectionID, projectIDs: projectIDs)
    }
    func authorizationRequired(connectionID: UUID, projectID: UUID) async -> Bool {
        await authorizationBarrier.contains(connectionID: connectionID, projectID: projectID)
    }
    func closeCopies(_ ids: [UUID]) { closedIDs.formUnion(ids) }
    func authorizationBarrierStore() -> PeerAuthorizationBarrierFixture { authorizationBarrier }
    func clearAuthorizationRequirement(connectionID: UUID, projectIDs: [UUID]) async {
        await authorizationBarrier.clear(connectionID: connectionID, projectIDs: projectIDs)
    }
    func readerDeniedProjects(for connectionID: UUID) -> Set<UUID> {
        deniedReaderProjects[connectionID, default: []]
    }
}

private actor PeerAuthorizationBarrierFixture {
    private var requiredProjects: [UUID: Set<UUID>] = [:]
    func require(connectionID: UUID, projectIDs: [UUID]) {
        requiredProjects[connectionID, default: []].formUnion(projectIDs)
    }
    func contains(connectionID: UUID, projectID: UUID) -> Bool {
        requiredProjects[connectionID, default: []].contains(projectID)
    }
    func clear(connectionID: UUID, projectIDs: [UUID]) {
        requiredProjects[connectionID]?.subtract(projectIDs)
    }
}

private actor PeerMemoryCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    private var deferredID: UUID?
    func deferRead(id: UUID?) { deferredID = id }
    func credential(deviceID: UUID) throws -> String? {
        if deviceID == deferredID { throw DesktopPeerCredentialError.legacyAuthorizationUnavailable }
        return values[deviceID]
    }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values[deviceID] = nil }
}

private enum PeerConnectionStoreWriteFailure: Error, Equatable {
    case injected
}

private actor FailingPeerConnectionStore: DesktopPeerConnectionStore {
    private let base: FileDesktopPeerConnectionStore
    private var failSave = false
    init(base: FileDesktopPeerConnectionStore) { self.base = base }
    func failNextSave() { failSave = true }
    func connectionIDs() async throws -> [UUID] { try await base.connectionIDs() }
    func load(id: UUID) async throws -> DesktopPeerConnection? { try await base.load(id: id) }
    func save(_ connection: DesktopPeerConnection) async throws {
        if failSave {
            failSave = false
            throw PeerConnectionStoreWriteFailure.injected
        }
        try await base.save(connection)
    }
    func remove(id: UUID) async throws { try await base.remove(id: id) }
}

private actor PeerWorkspaceProxy: DesktopPeerWorkspaceAccess {
    let workspace: DesktopPeerWorkspace
    var failRemoval = false
    init(_ workspace: DesktopPeerWorkspace) { self.workspace = workspace }
    func setFailRemoval(_ value: Bool) { failRemoval = value }
    func install(_ copy: DesktopPeerCopy) async throws -> URL { try await workspace.install(copy) }
    func open(id: UUID) async throws -> URL { try await workspace.open(id: id) }
    func capture(id: UUID, buffers: [OpenDocumentBuffer]) async throws -> DesktopPeerCopy { try await workspace.capture(id: id, buffers: buffers) }
    func captureDisk(id: UUID) async throws -> CorpusSnapshot { try await workspace.captureDisk(id: id) }
    func remove(id: UUID) async throws {
        if failRemoval { throw SyncError.invalidPath }
        try await workspace.remove(id: id)
    }
}

private enum PeerAccessMutation: Equatable, Sendable {
    case revokeDevice
    case withdrawProject
    case denyRequest
    case narrowSelection
}

private enum PeerGrantFailureTransition: CaseIterable {
    case pending
    case removed
    case narrowed
}

private actor PeerRemoteFixture: DesktopPeerRemote {
    let deviceID = UUID()
    let project: SharedProjectDescriptor
    private var currentProject: SharedProjectDescriptor
    private var access = DeviceAccess.pending
    private var projectShared = true
    private var reachable = true
    private var credentials: Set<String> = []
    private var nextCatalogueMutation: PeerAccessMutation?
    private var nextSnapshotMutation: PeerAccessMutation?
    private var nextFileMutation: PeerAccessMutation?
    private(set) var snapshotCount = 0
    init() throws {
        project = SharedProjectDescriptor(id: UUID(), name: "Shared notes", scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: ["docs"], documents: []))
        currentProject = project
    }
    func setAccess(_ value: DeviceAccess) { access = value }
    func withdrawProject() { projectShared = false }
    func restoreProject() { projectShared = true }
    func replaceProject(_ descriptor: SharedProjectDescriptor) { currentProject = descriptor }
    func setReachable(_ value: Bool) { reachable = value }
    func setNextCatalogueMutation(_ mutation: PeerAccessMutation) { nextCatalogueMutation = mutation }
    func setNextSnapshotMutation(_ mutation: PeerAccessMutation) { nextSnapshotMutation = mutation }
    func setNextFileMutation(_ mutation: PeerAccessMutation) { nextFileMutation = mutation }
    func probe(endpoint: URL) async throws -> Data { try checkReachable(); return Data(repeating: 1, count: 32) }
    func begin(endpoint: URL, fingerprint: Data, invitation: PairingInvitation?, name: String, credential: String, now: Date) async throws -> PairingChallenge {
        try checkReachable(); credentials.insert(credential)
        return PairingChallenge(id: deviceID, comparisonCode: "12345678", expiresAt: now.addingTimeInterval(300))
    }
    func status(_ connection: DesktopPeerConnection, credential: String) async throws -> DirectDeviceStatus {
        try checkReachable()
        guard credentials.contains(credential) else { throw PairingError.invalidCredential }
        return DirectDeviceStatus(access: access, projects: access == .authorized && projectShared ? [currentProject] : [])
    }
    func snapshot(_ descriptor: SharedProjectDescriptor, connection: DesktopPeerConnection, credential: String) async throws -> CorpusSnapshot {
        try apply(nextSnapshotMutation)
        nextSnapshotMutation = nil
        try checkReachable()
        guard access == .authorized, projectShared, credentials.contains(credential), descriptor.id == project.id else {
            throw SyncError.httpAccessDenied(operation: .snapshot, status: 403)
        }
        snapshotCount += 1
        let files = [CorpusFile(path: "docs/note.md", content: Data("remote".utf8))]
        return CorpusSnapshot(revision: CorpusRevision.make(files: files), files: files)
    }
    func catalogue(_ descriptor: SharedProjectDescriptor, connection: DesktopPeerConnection, credential: String) async throws -> RemoteProjectCatalogue {
        try apply(nextCatalogueMutation)
        let mutation = nextCatalogueMutation
        nextCatalogueMutation = nil
        try checkReachable()
        guard access == .authorized, projectShared, credentials.contains(credential), descriptor.id == project.id else {
            throw SyncError.httpAccessDenied(operation: .catalogue, status: 403)
        }
        if mutation == .denyRequest { throw SyncError.httpAccessDenied(operation: .catalogue, status: 403) }
        return RemoteProjectCatalogue(files: [])
    }
    func file(_ entry: RemoteFileEntry, projectID: UUID, connection: DesktopPeerConnection, credential: String) async throws -> CorpusFile {
        try apply(nextFileMutation)
        let mutation = nextFileMutation
        nextFileMutation = nil
        try checkReachable()
        guard access == .authorized, projectShared, credentials.contains(credential), projectID == project.id else {
            throw SyncError.httpAccessDenied(operation: .file, status: 403)
        }
        if mutation == .denyRequest || mutation == .narrowSelection {
            throw SyncError.httpAccessDenied(operation: .file, status: 403)
        }
        throw DesktopPeerLibraryError.unknownCopy
    }
    private(set) var publications: [DesktopPeerProposal] = []
    private var receipts: [UUID: DesktopPeerProposalReceipt] = [:]
    func publish(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws {
        try checkReachable()
        guard access == .authorized, credentials.contains(credential), proposal.projectID == project.id else { throw SyncError.revoked }
        publications.append(proposal)
    }
    func receipt(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws -> DesktopPeerProposalReceipt? {
        try checkReachable()
        guard access == .authorized, credentials.contains(credential), proposal.projectID == project.id else { throw SyncError.revoked }
        return receipts[proposal.id]
    }
    func acknowledge(_ proposal: DesktopPeerProposal, receipt: DesktopPeerProposalReceipt,
                     connection: DesktopPeerConnection, credential: String) async throws {
        try checkReachable()
        guard access == .authorized, credentials.contains(credential), proposal.projectID == project.id,
              receipts[proposal.id] == receipt else { throw SyncError.revoked }
    }
    private func checkReachable() throws { if !reachable { throw URLError(.notConnectedToInternet) } }
    private func apply(_ mutation: PeerAccessMutation?) throws {
        switch mutation {
        case .revokeDevice: access = .revoked
        case .withdrawProject: projectShared = false
        case .narrowSelection:
            currentProject = SharedProjectDescriptor(id: project.id, name: project.name, scope: project.scope,
                selection: try CorpusSelection(folders: [], documents: ["docs/other.md"]))
        case .denyRequest, nil: break
        }
    }
}
#endif
