import XCTest
@testable import LeonardoDesktopSync

final class SyncHelperSigningTests: XCTestCase {
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
