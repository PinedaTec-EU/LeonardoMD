import Foundation
import XCTest
import LeonardoDesktopSync

final class SyncHelperBuildIdentityTests: XCTestCase {
    func testLegacyHealthDecodesWithoutInventingARunningBuild() throws {
        let status = try JSONDecoder().decode(SyncHelperStatus.self,
            from: Data(#"{"enabled":true,"supportsRubricExchange":true}"#.utf8))
        XCTAssertNil(status.buildIdentity)
        XCTAssertTrue(status.supportsRubricExchange)
    }

    func testRealHostReportsTheIdentityCapturedAtLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = SyncHelperBuildIdentity(build: 200, bundlePath: "/Applications/LeonardoMD.app")
        let host = SyncHelperHost(preferencesURL: root.appendingPathComponent("preferences.json"),
                                  buildIdentity: identity)
        let data = try await host.perform(.status)
        let decoded = try JSONDecoder().decode(SyncHelperStatus.self, from: data)
        XCTAssertEqual(decoded.buildIdentity, identity)
    }
}
