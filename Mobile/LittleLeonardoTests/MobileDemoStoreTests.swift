import XCTest
import SwiftUI
import UIKit
import LeonardoCore
import LeonardoSync
@testable import LittleLeonardo

@MainActor
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

    func testMalformedPersonalCopyIsNotOverwrittenAtBootstrap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileDemoStore(root: root)
        _ = try store.load(.en)
        try "retained personal bytes".write(to: store.url(for: .en), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load(.en))
        XCTAssertEqual(try String(contentsOf: store.url(for: .en), encoding: .utf8), "retained personal bytes")
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

    func testProjectIdentityRowsKeepIncomingAndRecoveryRolesDistinct() throws {
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
                                                                              height: .greatestFiniteMagnitude)).height)),
                               accuracy: 1)
                compact.view.layoutIfNeeded()
                let iPad = host(name: name, identity: identity, width: 834, dynamicType: dynamicType)
                XCTAssertGreaterThan(iPad.view.bounds.width, compact.view.bounds.width)
                XCTAssertEqual(iPad.view.bounds.height,
                               max(104, ceil(iPad.sizeThatFits(in: CGSize(width: 834,
                                                                           height: .greatestFiniteMagnitude)).height)),
                               accuracy: 1)
                iPad.view.layoutIfNeeded()

                try captureIfRequested(compact, name: "\(identity.captureName)-iphone-\(dynamicType.captureName)",
                                       identity: identity, width: 390, dynamicType: dynamicType)
                try captureIfRequested(iPad, name: "\(identity.captureName)-ipad-\(dynamicType.captureName)",
                                       identity: identity, width: 834, dynamicType: dynamicType)
            }
        }
    }

    private func host(name: String, identity: ProjectIdentity, width: CGFloat,
                      dynamicType: DynamicTypeSize) -> UIHostingController<AnyView> {
        let view = MobileProjectIdentityLabel(name: name, identity: identity)
            .dynamicTypeSize(dynamicType)
            .padding(20)
            .frame(width: width, minHeight: 104, alignment: .leading)
            .background(MobileClassic.paper)
        let hosting = UIHostingController(rootView: AnyView(view))
        hosting.loadViewIfNeeded()
        hosting.view.frame = CGRect(x: 0, y: 0, width: width, height: 104)
        hosting.view.backgroundColor = .clear
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        let fittingHeight = max(104, ceil(hosting.sizeThatFits(in: CGSize(width: width,
                                                                            height: .greatestFiniteMagnitude)).height))
        hosting.view.frame.size.height = fittingHeight
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        return hosting
    }

    private func captureIfRequested(_ hosting: UIViewController, name: String,
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
        let image = renderer.image { _ in
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }
        let imageURL = directory.appendingPathComponent("\(name).png")
        try XCTUnwrap(image.pngData()).write(to: imageURL, options: .atomic)
        let metadata: [String: String] = [
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
