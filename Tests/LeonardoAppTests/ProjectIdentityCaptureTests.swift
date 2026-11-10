import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class ProjectIdentityCaptureTests: XCTestCase {
    func testCompactGuideProjectRows() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_PROJECT_IDENTITY_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_PROJECT_IDENTITY_EVIDENCE for the guide illustration")
        }
        let destination = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let previousLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previousLanguage }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let size = NSSize(width: 400, height: 160)
            let view = VStack(alignment: .leading, spacing: 8) {
                ProjectIdentityLabel(name: "My journey", identity: .local)
                ProjectIdentityLabel(name: "My journey", identity: .sharedFromThisDevice,
                                     detail: L10n.text("Selected content"))
                ProjectIdentityLabel(name: "My journey", identity: .received)
            }.padding(12).frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Color(hex: PaletteCatalog.leonardoClassic.tokens.surface))
                .environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: view)
            let image = destination.appendingPathComponent("project-identities-guide-\(language.rawValue).png")
            try await GuideCaptureSupport.captureNative(host, size: size, to: image,
                language: language.rawValue, state: "Production project identity rows; local, outgoing selected content and received",
                pixelScale: 1, route: "/native/project-identities", screen: "Project identity instructional illustration")
        }
    }

    func testNativeProjectIdentityRows() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_PROJECT_IDENTITY_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_PROJECT_IDENTITY_EVIDENCE for project-role captures")
        }
        let destination = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let previousLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previousLanguage }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for dark in [false, true] {
                for width in [220.0, 540.0] {
                    let size = NSSize(width: width, height: 340)
                    let view = VStack(alignment: .leading, spacing: 18) {
                        ProjectIdentityLabel(name: "My journey", identity: .local)
                        ProjectIdentityLabel(name: "My journey", identity: .sharedFromThisDevice,
                                             detail: L10n.text("Selected content"))
                        ProjectIdentityLabel(name: "My journey", identity: .received)
                        ProjectIdentityLabel(name: "Recovered journey", identity: .recoveryArchive)
                        Label(L10n.text("Notes"), systemImage: "folder")
                    }.padding(16).frame(width: width, height: size.height, alignment: .topLeading)
                        .background(dark ? Color(nsColor: .windowBackgroundColor) : Color(hex: PaletteCatalog.leonardoClassic.tokens.surface))
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let host = NSHostingView(rootView: view)
                    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    let image = destination.appendingPathComponent("project-identities-\(language.rawValue)-\(dark ? "dark" : "light")-\(Int(width)).png")
                    try await NativeViewCaptureSupport.capture(host, size: size, to: image)
                    try NativeViewCaptureSupport.writeProvenance(for: image,
                        screen: "Production project identity rows; local, outbound, received, recovery and child folder",
                        size: size, language: language.rawValue)
                }
            }
        }
    }
}
