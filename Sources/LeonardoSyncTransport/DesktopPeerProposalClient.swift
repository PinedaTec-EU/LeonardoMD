import Foundation
import CryptoKit
import LeonardoSync

public enum DesktopPeerProposalTransportError: Error, Equatable, Sendable { case accessDenied }

/// Sends only the immutable outbox capture. A submitted response means awaiting owner review.
public struct DesktopPeerProposalClient: Sendable {
    private let client: PinnedHTTPSClient
    private let receiptClient: PinnedHTTPSClient
    public init(endpoint: URL, certificateFingerprint: Data) throws {
        receiptClient = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: certificateFingerprint, maximumResponseBytes: DesktopPeerArchiveBudget.maximumEncodedBytes())
        client = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: certificateFingerprint, maximumResponseBytes: 4 * 1_024)
    }
    public func receipt(proposalID: UUID, projectID: UUID, selection: CorpusSelection, deviceID: UUID, credential: String) async throws -> DesktopPeerProposalReceipt? {
        let path = "/v1/devices/\(deviceID.uuidString)/projects/\(projectID.uuidString)/proposals/\(proposalID.uuidString)/receipt"
        let response = try await receiptClient.request(method: "GET", path: path, credential: credential)
        if response.status == 404 { return nil }
        if response.status == 403 { throw DesktopPeerProposalTransportError.accessDenied }
        guard response.status == 200 else { throw TransportError.unexpectedResponse }
        let receipt = try JSONDecoder().decode(DesktopPeerProposalReceipt.self, from: response.body)
        guard receipt.projectID == projectID, receipt.proposalID == proposalID else { throw SyncError.invalidSnapshot }
        try selection.validate(receipt.accepted)
        return receipt
    }

    public func acknowledge(_ proposal: DesktopPeerProposal, receipt: DesktopPeerProposalReceipt,
                            deviceID: UUID, credential: String) async throws {
        guard receipt.proposalID == proposal.id, receipt.projectID == proposal.projectID else {
            throw SyncError.invalidSnapshot
        }
        try proposal.selection.validate(receipt.accepted)
        let proof = try DesktopPeerReceiptAcknowledgement(receipt: receipt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let path = "/v1/devices/\(deviceID.uuidString)/projects/\(proposal.projectID.uuidString)/proposals/\(proposal.id.uuidString)/ack"
        let response = try await client.request(method: "POST", path: path, credential: credential, body: encoder.encode(proof))
        if response.status == 403 { throw DesktopPeerProposalTransportError.accessDenied }
        guard response.status == 200 || response.status == 204 else { throw TransportError.unexpectedResponse }
    }
    public func submit(_ proposal: DesktopPeerProposal, deviceID: UUID, credential: String) async throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(proposal)
        let upload = try DesktopPeerUpload(proposalID: proposal.id, projectID: proposal.projectID, byteCount: bytes.count,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        let base = "/v1/devices/\(deviceID.uuidString)/projects/\(proposal.projectID.uuidString)/proposals/"
        let started = try await client.request(method: "POST", path: base + "begin", credential: credential, body: encoder.encode(upload))
        var offset = try progress(started, expectedStatus: 200, upload: upload).receivedBytes
        while offset < bytes.count {
            try Task.checkCancellation()
            let end = min(bytes.count, offset + DesktopPeerUpload.maximumChunkBytes)
            let chunk = DesktopPeerUploadChunk(upload: upload, offset: offset, bytes: bytes.subdata(in: offset..<end))
            let response = try await client.request(method: "POST", path: base + "chunk", credential: credential, body: encoder.encode(chunk))
            let next = try progress(response, expectedStatus: 200, upload: upload)
            guard next.receivedBytes == end else { throw TransportError.unexpectedResponse }
            offset = next.receivedBytes
        }
        let submitted = try await client.request(method: "POST", path: base + "submit", credential: credential, body: encoder.encode(upload))
        let completed = try progress(submitted, expectedStatus: 202, upload: upload)
        guard completed.submitted, completed.receivedBytes == bytes.count else { throw TransportError.unexpectedResponse }
    }
    private func progress(_ response: HTTPResponse, expectedStatus: Int, upload: DesktopPeerUpload) throws -> DesktopPeerUploadProgress {
        if response.status == 409 { throw SyncError.publicationPending }
        if response.status == 403 { throw DesktopPeerProposalTransportError.accessDenied }
        guard response.status == expectedStatus else { throw TransportError.unexpectedResponse }
        let result = try JSONDecoder().decode(DesktopPeerUploadProgress.self, from: response.body)
        guard result.proposalID == upload.proposalID, result.receivedBytes >= 0, result.receivedBytes <= upload.byteCount else { throw TransportError.unexpectedResponse }
        return result
    }
}
