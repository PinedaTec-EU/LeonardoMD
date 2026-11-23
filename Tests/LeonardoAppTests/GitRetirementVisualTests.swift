import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class GitRetirementVisualTests: XCTestCase {
    func testCaptureSystemGitAndDirectSyncWithoutPublicationUI() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_GIT_RETIREMENT_EVIDENCE"] else {
            throw XCTSkip("Requires an explicit native component capture destination")
        }
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Synthetic Documents")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("# Synthetic document\n".utf8).write(to: source.appendingPathComponent("note.md"))
        let preferences = root.appendingPathComponent("preferences.json")
        let session = AppSession(preferencesURL: preferences)
        session.projectURL = source
        session.projectConfiguration.git.enabled = true
        session.git = GitRepository(rootURL: source)
        _ = try await session.git?.initialize()
        await session.refreshGit()
        XCTAssertEqual(session.gitStatus?.state, .changesPending)
        let controller = DesktopSyncController(preferencesURL: preferences, configurations: ConfigurationStore())
        await controller.initialize()
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let git = NSHostingView(rootView: GitPanel(session: session).modifier(SessionAppearance(session: session))
                .background(Color(nsColor: .windowBackgroundColor)))
            try await NativeViewCaptureSupport.capture(git, size: NSSize(width: 820, height: 700),
                to: destination.appendingPathComponent("system-git-\(language.rawValue).png"))
            let sync = NSHostingView(rootView: MobileSyncPreferencesView(session: session, controller: controller)
                .padding().frame(width: 580, height: 620))
            try await NativeViewCaptureSupport.capture(sync, size: NSSize(width: 580, height: 620),
                to: destination.appendingPathComponent("direct-sync-\(language.rawValue).png"))
        }
    }
}
