import AppKit
import SwiftUI
import XCTest
import Vision
import LeonardoCore
import LeonardoSync
@testable import LeonardoApp

@MainActor
final class SynchronizationPreferencesTests: XCTestCase {
    func testPrincipalRolesShareOneServiceLifecycle() {
        XCTAssertTrue(DesktopSyncController.shared.helper === DesktopPeerController.shared.helper,
                      "Both roles must observe the common service disable immediately")
    }

    func testHelperExplanationStatesThatDisablingSyncStopsBothRolesWhileAppIsOpen() {
        let original = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = original }

        LanguageSettings.shared.language = .english
        XCTAssertTrue(SyncHelperPreferencesSection.explanation.contains(
            "When off, sharing and remote access stop even with LeonardoMD open."
        ))

        LanguageSettings.shared.language = .spanish
        XCTAssertTrue(SyncHelperPreferencesSection.explanation.contains(
            "Al desactivarlo, se cortan el uso compartido y el acceso remoto aunque LeonardoMD siga abierto."
        ))
    }

}
