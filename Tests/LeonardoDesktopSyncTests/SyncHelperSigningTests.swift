import XCTest
@testable import LeonardoDesktopSync

final class SyncHelperSigningTests: XCTestCase {
    func testSignedPackagedComponentsSatisfyMutualRequirements() throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_SYNC_SIGNING_BUNDLE"] else {
            throw XCTSkip("Set LEONARDO_SYNC_SIGNING_BUNDLE to inspect a signed package without registering it")
        }
        let bundle = URL(fileURLWithPath: path)
        let helper = bundle.appendingPathComponent("Contents/MacOS/" + SyncHelperContract.executableName)
        XCTAssertFalse(try SyncHelperSigning.requirement(for: bundle,
            identifier: SyncHelperContract.appIdentifier, matching: helper).isEmpty)
        XCTAssertFalse(try SyncHelperSigning.requirement(for: helper,
            identifier: SyncHelperContract.serviceName, matching: bundle).isEmpty)
    }

    func testCorrectIdentifierAndOwnerTeamAreBothRequired() throws {
        try SyncHelperSigning.validate(identifier: SyncHelperContract.serviceName, team: "OWNERTEAM",
            expectedIdentifier: SyncHelperContract.serviceName, ownerTeam: "OWNERTEAM")
        for (identifier, team, owner) in [("other.app", "OWNERTEAM", "OWNERTEAM"),
                                          (SyncHelperContract.serviceName, "OTHERTEAM", "OWNERTEAM"),
                                          (SyncHelperContract.serviceName, nil, nil)] {
            XCTAssertThrowsError(try SyncHelperSigning.validate(identifier: identifier, team: team,
                expectedIdentifier: SyncHelperContract.serviceName, ownerTeam: owner))
        }
    }
}
