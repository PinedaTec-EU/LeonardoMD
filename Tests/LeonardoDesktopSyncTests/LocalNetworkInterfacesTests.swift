#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

final class LocalNetworkInterfacesTests: XCTestCase {
    func testLANAndPrivateOverlayInterfaceBoundaries() {
        XCTAssertTrue(LocalNetworkInterfaces.isSelectable(interface: "en0", address: "192.168.1.20"))
        XCTAssertTrue(LocalNetworkInterfaces.isSelectable(interface: "en0", address: "10.0.0.20"))
        XCTAssertFalse(LocalNetworkInterfaces.isSelectable(interface: "en0", address: "100.64.0.1", allowPrivateOverlay: true))
        XCTAssertFalse(LocalNetworkInterfaces.isSelectable(interface: "en0", address: "8.8.8.8", allowPrivateOverlay: true))

        XCTAssertFalse(LocalNetworkInterfaces.isSelectable(interface: "utun7", address: "100.64.0.1"))
        XCTAssertFalse(LocalNetworkInterfaces.isSelectable(interface: "utun7", address: "100.63.255.255", allowPrivateOverlay: true))
        XCTAssertTrue(LocalNetworkInterfaces.isSelectable(interface: "utun7", address: "100.64.0.1", allowPrivateOverlay: true))
        XCTAssertTrue(LocalNetworkInterfaces.isSelectable(interface: "utun7", address: "100.127.255.254", allowPrivateOverlay: true))
        XCTAssertFalse(LocalNetworkInterfaces.isSelectable(interface: "utun7", address: "100.128.0.1", allowPrivateOverlay: true))
        XCTAssertFalse(LocalNetworkInterfaces.isSelectable(interface: "utun7", address: "2001:db8::1", allowPrivateOverlay: true))
    }

    func testDiscoveryNeverAddsOverlayWhenOptInIsOffAndKeepsLANFirst() {
        let automatic = LocalNetworkInterfaces.addresses()
        let optedIn = LocalNetworkInterfaces.addresses(allowPrivateOverlay: true)
        XCTAssertTrue(automatic.allSatisfy { !LocalNetworkAddress.isPrivateOverlay($0) })
        let firstOverlay = optedIn.firstIndex { LocalNetworkAddress.isPrivateOverlay($0) }
        if let firstOverlay {
            XCTAssertTrue(optedIn[..<firstOverlay].allSatisfy { !LocalNetworkAddress.isPrivateOverlay($0) })
        }
    }

    func testRuntimeRejectsOverlayWithoutExplicitOptInBeforeProvisioningIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = DesktopDirectRuntime(root: root, credentials: NetworkPolicyCredentials(), now: { Date() })
        do {
            _ = try await runtime.start(host: "100.64.0.1", port: 0, projects: [])
            XCTFail("Private overlay was enabled implicitly")
        } catch {
            XCTAssertEqual(error as? TransportError, .invalidEndpoint)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}

private actor NetworkPolicyCredentials: DeviceCredentialStore {
    func credential(deviceID: UUID) -> String? { nil }
    func save(_ credential: String, deviceID: UUID) {}
    func remove(deviceID: UUID) {}
}
#endif
