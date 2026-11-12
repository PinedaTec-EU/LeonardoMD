import Foundation
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class SessionDocumentAccessTests: XCTestCase {
    func testRevocationCancelsPendingMarkdownAndPackageLoadsWithoutClearingUnrelatedDrafts() async throws {
        for package in [false, true] {
            for hasDraft in [false, true] {
                try await checkPendingRevocation(package: package, hasDraft: hasDraft)
            }
        }
    }

    private func checkPendingRevocation(package: Bool, hasDraft: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LeonardoPendingAccess-" + UUID().uuidString)
        let revoked = root.appendingPathComponent("revoked")
        try FileManager.default.createDirectory(at: revoked, withIntermediateDirectories: true)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let session = tabs.activeSession
        var resume: CheckedContinuation<Void, Never>?
        defer {
            resume?.resume()
            tabs.stop()
            try? FileManager.default.removeItem(at: root)
        }
        session.authorizePath = { _, _ in }
        let local = root.appendingPathComponent("local.md")
        if hasDraft {
            try "saved local".write(to: local, atomically: true, encoding: .utf8)
            await session.openDocument(local)
            session.content = "unrelated draft"
            session.contentChanged()
        }
        let originalURL = session.documentURL
        let originalContent = session.content
        let target = revoked.appendingPathComponent(package ? "incoming.mdlz" : "incoming.md")
        if package {
            let template = revoked.appendingPathComponent("incoming.mdlf")
            let document = LeonardoDocument(body: "Incoming", metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(title: "Incoming", kind: .document)))
            let source = try LeonardoFormatParser.serialize(document)
            try LeonardoPackageTransport.export(documentURL: template, content: source, to: target)
        } else {
            try "incoming secret".write(to: target, atomically: true, encoding: .utf8)
        }
        let originalBytes = try Data(contentsOf: target)
        session.authorizePath = { url, _ in
            guard url.standardizedFileURL == target.standardizedFileURL else { return }
            await withCheckedContinuation { resume = $0 }
        }
        let opening = Task { @MainActor in
            if package { return await session.openLeonardoPackage(target, extractingTo: nil) }
            await session.openDocument(target)
            return session.documentURL == target
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while resume == nil && ContinuousClock.now < deadline { await Task.yield() }
        let continuation = try XCTUnwrap(resume)
        var revocationFinished = false
        let revocation = Task { @MainActor in
            await tabs.revokeWorkspaces([revoked])
            revocationFinished = true
        }
        let revokedDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !session.pendingDocumentAccesses.values.contains(where: \.revoked), ContinuousClock.now < revokedDeadline {
            await Task.yield()
        }
        XCTAssertTrue(session.pendingDocumentAccesses.values.contains(where: \.revoked))
        XCTAssertFalse(revocationFinished)
        continuation.resume()
        resume = nil
        let opened = await opening.value
        await revocation.value
        XCTAssertFalse(opened)
        XCTAssertFalse(session.stopped)
        XCTAssertTrue(tabs.tabs.contains { $0.session === session })
        XCTAssertEqual(session.documentURL, originalURL)
        XCTAssertEqual(session.content, originalContent)
        XCTAssertEqual(session.isDirty, hasDraft)
        XCTAssertTrue(session.pendingDocumentAccesses.isEmpty)
        XCTAssertEqual(session.fileOperationCount, 0)
        XCTAssertNil(session.packageWorkspace)
        XCTAssertEqual(try Data(contentsOf: target), originalBytes)
    }
}
