import XCTest
@testable import LeonardoSync

final class DesktopPeerReceiptAcknowledgementTests: XCTestCase {
    func testProofContainsOnlyAcceptedRevisionAndDigest() throws {
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let accepted = CorpusSnapshot(revision: "accepted", files: [
            CorpusFile(path: "docs/note.md", content: Data("remote".utf8))
        ])
        let receipt = try DesktopPeerProposalReceipt(proposalID: UUID(), projectID: UUID(), accepted: accepted)
        let proof = try DesktopPeerReceiptAcknowledgement(receipt: receipt)
        XCTAssertEqual(proof.acceptedRevision, accepted.revision)
        XCTAssertEqual(proof.acceptedDigest, CorpusRevision.make(files: accepted.files))
        let decoded = try JSONDecoder().decode(DesktopPeerReceiptAcknowledgement.self,
            from: JSONEncoder().encode(proof))
        XCTAssertEqual(decoded, proof)
        try selection.validate(receipt.accepted)
    }
}
