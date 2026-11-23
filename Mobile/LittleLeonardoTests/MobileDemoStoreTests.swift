import XCTest
import SwiftUI
import UIKit
import LeonardoCore
import LeonardoSync
@testable import LittleLeonardo

final class MobileDemoStoreTests: XCTestCase {
    func testBootstrapPreservesAnswersAndResetOnlyAffectsSelectedLocale() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileDemoStore(root: root)
        let spanish = try store.load(.es)
        let english = try store.load(.en)
        let document = try LeonardoFormatParser.parse(spanish)
        let filled = try XCTUnwrap(document.applyingFormValues(["name": .string("Review sample")]))
        let replacement = try LeonardoFormatParser.serialize(filled)
        try store.save(replacement, language: .es)
        XCTAssertEqual(try MobileDemoStore(root: root).load(.es), replacement)
        XCTAssertEqual(try store.load(.en), english)
        XCTAssertEqual(try store.reset(.en), english)
        XCTAssertEqual(try store.load(.es), replacement)
        XCTAssertEqual(try store.reset(.es), spanish)
    }

    func testNewDemoContentRevisionUsesFreshCopiesAndPreservesOlderAnswers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldRevision = MobileDemoStore(root: root.appendingPathComponent("v1"))
        let newRevision = MobileDemoStore(root: root.appendingPathComponent("v2"))
        let original = try oldRevision.load(.es)
        let document = try LeonardoFormatParser.parse(original)
        let filled = try XCTUnwrap(document.applyingFormValues(["name": .string("Older revision answer")]))
        let saved = try LeonardoFormatParser.serialize(filled)
        try oldRevision.save(saved, language: .es)

        XCTAssertEqual(try oldRevision.load(.es), saved)
        XCTAssertEqual(try newRevision.load(.es), try newRevision.template(.es),
                       "A newer bundled content revision must bootstrap its own fresh personal copy")
        XCTAssertNotEqual(try newRevision.load(.es), saved)
        XCTAssertEqual(try oldRevision.load(.es), saved,
                       "Opening a newer revision must not overwrite answers from an older revision")
    }

    func testMalformedPersonalCopyIsNotOverwrittenAtBootstrap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileDemoStore(root: root)
        _ = try store.load(.en)
        try "retained personal bytes".write(to: store.url(for: .en), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load(.en))
        XCTAssertEqual(try String(contentsOf: store.url(for: .en), encoding: .utf8), "retained personal bytes")
    }

    @MainActor func testProjectDeletionSurvivesRestartAndOnlyNewDemoRevisionRestoresVisibility() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("removals.json")
        let projectID = UUID()
        let lifecycle = MobileProjectLifecycle(url: url, demoRevision: 1)
        XCTAssertTrue(lifecycle.demoIsVisible)
        try lifecycle.deleteDemo()
        try lifecycle.deleteProject(projectID)
        let reopened = MobileProjectLifecycle(url: url, demoRevision: 1)
        try reopened.reload()
        XCTAssertFalse(reopened.demoIsVisible)
        XCTAssertTrue(reopened.isDeleted(projectID))
        let updated = MobileProjectLifecycle(url: url, demoRevision: 2)
        try updated.reload()
        XCTAssertTrue(updated.demoIsVisible)
        XCTAssertTrue(updated.isDeleted(projectID))
        try updated.deleteDemo()
        XCTAssertFalse(updated.demoIsVisible)
        let downgraded = MobileProjectLifecycle(url: url, demoRevision: 1)
        try downgraded.reload()
        XCTAssertFalse(downgraded.demoIsVisible, "An older bundled revision must not restore a deleted demo")
        try updated.restoreDemo()
        let restored = MobileProjectLifecycle(url: url, demoRevision: 2)
        try restored.reload()
        XCTAssertTrue(restored.demoIsVisible)
        XCTAssertTrue(restored.isDeleted(projectID))
    }

    @MainActor func testDemoRecoveryPreservesSavedAnswers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileDemoStore(root: root.appendingPathComponent("Demo"))
        let text = try store.load(.es)
        let document = try LeonardoFormatParser.parse(text)
        let filled = try XCTUnwrap(document.applyingFormValues(["name": .string("Retained answer")]))
        let saved = try LeonardoFormatParser.serialize(filled)
        try store.save(saved, language: .es)
        let lifecycle = MobileProjectLifecycle(url: root.appendingPathComponent("removals.json"))
        try lifecycle.deleteDemo()
        try lifecycle.restoreDemo()
        XCTAssertEqual(try store.load(.es), saved)
    }

    @MainActor func testRemovingDownloadedProjectDeletesBytesAndSuppressesRecreatedCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let corpus = root.appendingPathComponent("Corpus")
        let store = OfflineCorpusStore(root: corpus)
        let project = try OfflineProject(name: "Sample", mode: .direct, scope: CorpusScope(folder: ""),
            snapshot: CorpusSnapshot(revision: "r1", files: [CorpusFile(path: "read.md", content: Data("sample".utf8))]))
        let sibling = try OfflineProject(name: "Unrelated", mode: .direct, scope: CorpusScope(folder: ""),
            snapshot: CorpusSnapshot(revision: "r1", files: [CorpusFile(path: "keep.md", content: Data("keep".utf8))]))
        try await store.save(project)
        try await store.save(sibling)
        let library = MobileLibrary(rootURL: corpus)
        await library.reload()
        XCTAssertEqual(library.projects.count, 2)
        let file = try XCTUnwrap(project.files.first)
        let descriptor = SharedProjectDescriptor(id: project.id, name: project.name, scope: project.scope)
        try await library.downloads.update(id: project.id, descriptor: descriptor,
            catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: file)]))
        library.downloads.fetch = { _, _ in file }
        let downloaded = try await library.downloads.open(id: project.id, path: file.path)
        XCTAssertEqual(downloaded, file)
        XCTAssertEqual(library.downloads.projects.map(\.id), [project.id])
        await library.deleteProject(project.id)
        XCTAssertFalse(library.downloads.projects.contains { $0.id == project.id })
        let downloadCache = OnDemandCache(root: root.appendingPathComponent("Downloads"))
        let remainingDownloads = try await downloadCache.projects()
        XCTAssertFalse(remainingDownloads.contains { $0.id == project.id })
        do {
            _ = try await library.downloads.open(id: project.id, path: file.path)
            XCTFail("A deleted project must not remain readable from the downloads library")
        } catch {
            XCTAssertEqual(error as? SyncError, .revoked)
        }
        XCTAssertEqual(library.projects.map(\.id), [sibling.id])
        let deleted = try await store.load(id: project.id)
        XCTAssertNil(deleted)
        // A late malformed cache recreation cannot defeat the user's durable
        // removal intent or make an otherwise usable library fail to reload.
        let lateCache = corpus.appendingPathComponent(project.id.uuidString).appendingPathExtension("json")
        try Data("not a project snapshot".utf8).write(to: lateCache, options: .atomic)
        let reopened = MobileLibrary(rootURL: corpus)
        await reopened.reload()
        XCTAssertNil(reopened.error)
        XCTAssertEqual(reopened.projects.map(\.id), [sibling.id])
        XCTAssertTrue(reopened.libraryProjects.contains { $0.id == "bundled-demo" })
    }

    @MainActor func testFailedDeletionDoesNotChangeVisibility() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root)
        let lifecycle = MobileProjectLifecycle(url: root.appendingPathComponent("removals.json"))
        XCTAssertThrowsError(try lifecycle.deleteDemo())
        XCTAssertTrue(lifecycle.demoIsVisible)
        let id = UUID()
        XCTAssertThrowsError(try lifecycle.deleteProject(id))
        XCTAssertFalse(lifecycle.isDeleted(id))
    }

    func testBothBundledTemplatesHaveRealFieldsAndOfflineExamples() throws {
        let store = MobileDemoStore()
        for language in MobileDemoStore.Language.allCases {
            let source = try store.template(language)
            let document = try LeonardoFormatParser.parse(source)
            XCTAssertEqual(document.metadata.fields.count, 4)
            XCTAssertTrue(source.contains("```mermaid"))
            XCTAssertTrue(source.contains("```vega-lite"))
            XCTAssertTrue(source.contains("\\tag{1}"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.resources.appendingPathComponent("assets/demo.png").path))
        }
    }

    @MainActor func testProjectIdentityRowsKeepIncomingAndRecoveryRolesDistinct() throws {
        // A direct cache is still a received project on iOS, including when it is offline.
        let direct = try OfflineProject(name: "Trip", mode: .direct,
                                        scope: CorpusScope(folder: ""),
                                        snapshot: CorpusSnapshot(revision: "offline", files: []))
        let recovery = try decodedLegacyRecoveryProject()
        let received = MobileProjectIdentityLabel(name: direct.name, identity: direct.projectIdentity)
        let recoveryLabel = MobileProjectIdentityLabel(name: recovery.name, identity: recovery.projectIdentity)

        XCTAssertEqual(ProjectIdentity.projectSymbolName, "square.stack.3d.up")
        XCTAssertEqual(ProjectIdentity.received.indicatorSymbolName, "network")
        XCTAssertNil(ProjectIdentity.recoveryArchive.indicatorSymbolName)
        XCTAssertEqual(MobileLibraryProject.demo.projectIdentity, .local,
                       "The bundled Demo remains local while downloaded projects are received")
        assertReceived(direct.projectIdentity)
        XCTAssertTrue(recovery.isRecoveryArchive)
        assertRecovery(recovery.projectIdentity)
        XCTAssertEqual(received.bilingualRole, "Recibido de otro equipo · Received from another device")
        XCTAssertEqual(recoveryLabel.bilingualRole, "Archivo de recuperación · Recovery archive")
        XCTAssertEqual(received.accessibilityText, "Trip, Recibido de otro equipo · Received from another device")
        XCTAssertEqual(recoveryLabel.accessibilityText, "Legacy work, Archivo de recuperación · Recovery archive")
        XCTAssertFalse(received.accessibilityText.localizedCaseInsensitiveContains("shared"))
        XCTAssertFalse(recoveryLabel.accessibilityText.localizedCaseInsensitiveContains("network"))

        for dynamicType in [DynamicTypeSize.large, .accessibility3] {
            for (name, identity) in [(direct.name, direct.projectIdentity),
                                     (recovery.name, recovery.projectIdentity)] {
                let compact = host(name: name, identity: identity, width: 390, dynamicType: dynamicType)
                XCTAssertEqual(compact.view.bounds.width, 390, accuracy: 0.5)
                XCTAssertEqual(compact.view.bounds.height,
                               max(104, ceil(compact.sizeThatFits(in: CGSize(width: 390,
                                                                              height: CGFloat.greatestFiniteMagnitude)).height)),
                               accuracy: 1)
                compact.view.layoutIfNeeded()
                let iPad = host(name: name, identity: identity, width: 834, dynamicType: dynamicType)
                XCTAssertGreaterThan(iPad.view.bounds.width, compact.view.bounds.width)
                XCTAssertEqual(iPad.view.bounds.height,
                               max(104, ceil(iPad.sizeThatFits(in: CGSize(width: 834,
                                                                           height: CGFloat.greatestFiniteMagnitude)).height)),
                               accuracy: 1)
                iPad.view.layoutIfNeeded()

                try captureIfRequested(compact, name: "\(identity.captureName)-iphone-\(dynamicType.captureName)",
                                       identity: identity, width: 390, dynamicType: dynamicType)
                try captureIfRequested(iPad, name: "\(identity.captureName)-ipad-\(dynamicType.captureName)",
                                       identity: identity, width: 834, dynamicType: dynamicType)
            }
        }
    }

    @MainActor private func host(name: String, identity: ProjectIdentity, width: CGFloat,
                                 dynamicType: DynamicTypeSize) -> UIHostingController<AnyView> {
        let view = MobileProjectIdentityLabel(name: name, identity: identity)
            .dynamicTypeSize(dynamicType)
            .padding(20)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 104, alignment: .leading)
            .background(MobileClassic.paper)
        let hosting = UIHostingController(rootView: AnyView(view))
        hosting.safeAreaRegions = []
        hosting.loadViewIfNeeded()
        hosting.view.frame = CGRect(x: 0, y: 0, width: width, height: 104)
        hosting.view.backgroundColor = UIColor.clear
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        let fittingHeight = max(104, ceil(hosting.sizeThatFits(in: CGSize(width: width,
                                                                            height: CGFloat.greatestFiniteMagnitude)).height))
        hosting.view.frame.size.height = fittingHeight
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        return hosting
    }

    @MainActor private func captureIfRequested(_ hosting: UIViewController, name: String,
                                               identity: ProjectIdentity, width: CGFloat,
                                               dynamicType: DynamicTypeSize) throws {
        guard let output = evidenceValue("LEONARDO_PROJECT_IDENTITY_EVIDENCE"),
              !output.isEmpty,
              let sourceSHA = evidenceValue("LEONARDO_PROJECT_IDENTITY_SOURCE_SHA"),
              !sourceSHA.isEmpty else { return }
        let window = UIWindow(frame: hosting.view.bounds)
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = hosting.view.bounds.size
        let renderer = UIGraphicsImageRenderer(size: size)
        let capturedAt = ISO8601DateFormatter().string(from: Date())
        let image = renderer.image { _ in
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }
        let imageURL = directory.appendingPathComponent("\(name).png")
        try XCTUnwrap(image.pngData()).write(to: imageURL, options: .atomic)
        let metadata: [String: String] = [
            "captured_at": capturedAt,
            "component": "MobileProjectIdentityLabel",
            "role": identity.captureName,
            "source_sha": sourceSHA,
            "width_points": String(Int(width)),
            "height_points": String(Int(size.height)),
            "dynamic_type": dynamicType.captureName,
            "platform": "iOS native UIHostingController",
            "state": identity.evidenceState
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: directory.appendingPathComponent("\(name).metadata.json"), options: .atomic)
    }

    private func evidenceValue(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_\(key)"]
    }

    private func decodedLegacyRecoveryProject() throws -> OfflineProject {
        let bytes = Data(repeating: 1, count: 8).base64EncodedString()
        let publishedBytes = Data(repeating: 2, count: 8).base64EncodedString()
        let files: [[String: Any]] = [
            ["path": "docs/a.md", "content": bytes, "isUnsavedBuffer": false]
        ]
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Legacy work",
            "mode": "git",
            "scope": ["folder": "docs"],
            "base": ["revision": "original", "files": files],
            "files": [],
            "publication": "sent",
            "publishedRevision": "published-commit",
            "publishedFiles": [["path": "docs/a.md", "content": publishedBytes, "isUnsavedBuffer": false]]
        ]
        return try JSONDecoder().decode(OfflineProject.self,
                                        from: JSONSerialization.data(withJSONObject: payload))
    }

    private func assertReceived(_ identity: ProjectIdentity, file: StaticString = #filePath,
                                line: UInt = #line) {
        guard case .received = identity else {
            XCTFail("A direct iOS cache must remain received", file: file, line: line)
            return
        }
    }

    private func assertRecovery(_ identity: ProjectIdentity, file: StaticString = #filePath,
                                line: UInt = #line) {
        guard case .recoveryArchive = identity else {
            XCTFail("A legacy Git cache must remain a recovery archive", file: file, line: line)
            return
        }
    }
}

private extension ProjectIdentity {
    var captureName: String {
        switch self {
        case .received: "received"
        case .recoveryArchive: "recovery"
        case .local: "local"
        case .sharedFromThisDevice: "shared"
        case .unknown: "unknown"
        }
    }

    var evidenceState: String {
        switch self {
        case .received: "received from another device"
        case .recoveryArchive: "recovery archive"
        default: title(languageCode: "en")
        }
    }
}

private extension DynamicTypeSize {
    var captureName: String {
        switch self {
        case .large: "large"
        case .accessibility3: "accessibility3"
        default: "dynamic"
        }
    }
}

final class MobileDirectConnectionStoreTests: XCTestCase {
    func testSharedFileStatusPrioritizesLiveTransferAndDownloadFailure() {
        XCTAssertEqual(MobileSharedFileStatus.resolve(isDownloading: true, hasFailed: true,
            isAvailableOffline: false, isRetained: true, isDownloaded: false), .downloading)
        XCTAssertEqual(MobileSharedFileStatus.resolve(isDownloading: false, hasFailed: true,
            isAvailableOffline: false, isRetained: true, isDownloaded: false), .failed)
        XCTAssertEqual(MobileSharedFileStatus.resolve(isDownloading: false, hasFailed: false,
            isAvailableOffline: true, isRetained: true, isDownloaded: true), .availableOffline)
        XCTAssertEqual(MobileSharedFileStatus.resolve(isDownloading: false, hasFailed: false,
            isAvailableOffline: false, isRetained: true, isDownloaded: false), .offlinePending)
    }

    func testIgnoredProjectStaysDismissedUntilItsGrantChanges() throws {
        let projectID = UUID()
        let scope = try CorpusScope(folder: "")
        let selection = try CorpusSelection(folders: [], documents: ["docs/one.md"])
        let original = SharedProjectDescriptor(id: projectID, name: "Notes", scope: scope, selection: selection)
        let renamed = SharedProjectDescriptor(id: projectID, name: "Renamed notes", scope: scope, selection: selection)
        let changedGrant = SharedProjectDescriptor(id: projectID, name: "Renamed notes",
            scope: scope, selection: try CorpusSelection(folders: [], documents: ["docs/two.md"]))
        var connection = MobileDirectConnection(deviceID: UUID(), endpoint: URL(string: "https://mac.local")!,
            fingerprint: Data(repeating: 1, count: 32), projectIDs: [projectID], comparisonCode: nil,
            capabilities: [])
        connection.projectDescriptors = [original]
        connection.ignoredProjectIDs.insert(projectID)

        connection.reconcileIgnoredProjectGrants(with: [renamed])
        XCTAssertTrue(connection.ignoredProjectIDs.contains(projectID), "A label change does not change access")

        connection.projectDescriptors = [renamed]
        connection.reconcileIgnoredProjectGrants(with: [changedGrant])
        XCTAssertFalse(connection.ignoredProjectIDs.contains(projectID),
                       "A changed host selection must return the project to review")
    }

    func testIgnoredProjectIsClearedWhenHostRemovesItsGrant() throws {
        let projectID = UUID()
        let descriptor = SharedProjectDescriptor(id: projectID, name: "Notes", scope: try CorpusScope(folder: ""))
        var connection = MobileDirectConnection(deviceID: UUID(), endpoint: URL(string: "https://mac.local")!,
            fingerprint: Data(repeating: 1, count: 32), projectIDs: [projectID], comparisonCode: nil,
            capabilities: [])
        connection.projectDescriptors = [descriptor]
        connection.ignoredProjectIDs.insert(projectID)

        connection.reconcileIgnoredProjectGrants(with: [])

        XCTAssertFalse(connection.ignoredProjectIDs.contains(projectID))
    }
}
