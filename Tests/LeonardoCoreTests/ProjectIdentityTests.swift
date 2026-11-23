import XCTest
@testable import LeonardoCore

final class ProjectIdentityTests: XCTestCase {
    func testReceivingDoesNotAddAnOutgoingSharingBadge() {
        XCTAssertEqual(ProjectIdentity.projectSymbolName, "square.stack.3d.up")
        XCTAssertEqual(ProjectIdentity.received.indicatorSymbolName, "network")
        XCTAssertEqual(ProjectIdentity.sharedFromThisDevice.indicatorSymbolName, "person.2")
        for identity in [ProjectIdentity.local, .recoveryArchive, .unknown] {
            XCTAssertNil(identity.indicatorSymbolName)
        }
    }

    func testBothLanguagesDescribeDirectionRatherThanConnectivity() {
        XCTAssertEqual(ProjectIdentity.received.title(languageCode: "es"), "Recibido de otro equipo")
        XCTAssertEqual(ProjectIdentity.received.title(languageCode: "en"), "Received from another device")
        XCTAssertEqual(ProjectIdentity.sharedFromThisDevice.title(languageCode: "es"), "Compartido desde este equipo")
        XCTAssertEqual(ProjectIdentity.sharedFromThisDevice.title(languageCode: "en"), "Shared from this device")
        XCTAssertEqual(ProjectIdentity.recoveryArchive.title(languageCode: "es-ES"), "Archivo de recuperación")
        XCTAssertEqual(ProjectIdentity.unknown.title(languageCode: "en"), "Project")
    }
}
