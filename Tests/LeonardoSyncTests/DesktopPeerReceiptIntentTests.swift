import Foundation
import XCTest
@testable import LeonardoSync

final class DesktopPeerReceiptIntentTests: XCTestCase {
    func testLegacyAfterFieldDecodesWithoutDiskBaselineOrRetainedBuffers() throws {
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let baseline = CorpusSnapshot(revision: "base", files: [
            CorpusFile(path: "docs/note.md", content: Data("base".utf8))
        ])
        let accepted = CorpusSnapshot(revision: "accepted", files: [
            CorpusFile(path: "docs/note.md", content: Data("remote".utf8))
        ])
        let copy = try DesktopPeerCopy(connectionID: UUID(), remoteProjectID: UUID(), name: "Peer",
                                       selection: selection, snapshot: baseline)
        let proposal = try DesktopPeerProposal(projectID: copy.remoteProjectID, selection: selection,
                                               base: baseline, proposed: baseline)
        let receipt = try DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: proposal.projectID,
                                                     accepted: accepted)
        var merged = copy
        try merged.acknowledge(proposal, receipt: receipt)
        let intent = try DesktopPeerReceiptIntent(copyID: copy.id, transactionID: UUID(), proposal: proposal,
                                                  receipt: receipt, merged: merged, before: baseline,
                                                  appliedSnapshot: accepted)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        legacy["after"] = legacy.removeValue(forKey: "appliedSnapshot")
        let decoded = try JSONDecoder().decode(DesktopPeerReceiptIntent.self,
                                                from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.after, accepted)
        XCTAssertNil(decoded.diskAtSend)
        XCTAssertTrue(decoded.retainedBufferPaths.isEmpty)
    }
}
