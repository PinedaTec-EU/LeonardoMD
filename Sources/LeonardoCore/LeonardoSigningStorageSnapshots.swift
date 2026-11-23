import Foundation

extension LeonardoGuidedSigningSession {
    // Local sidecars can refer to the already stored session snapshot. The
    // marker never enters an exchange or a canonical signature payload.
    private static let storedSnapshotReference = LeonardoSigningSnapshot(
        source: "",
        sourceSHA256: Data(),
        resources: [],
        capturedAt: Date(timeIntervalSinceReferenceDate: 0)
    )

    func compactingProofSnapshotsForStorage() throws -> Self {
        guard !hasStoredSnapshotReference else { throw LeonardoSigningError.storageFailure }
        guard let snapshot else { return self }
        return replacingProofSnapshots(matching: snapshot, with: Self.storedSnapshotReference)
    }

    func restoringProofSnapshotsFromStorage() throws -> Self {
        guard hasStoredSnapshotReference else { return self }
        guard let snapshot else { throw LeonardoSigningError.storageFailure }
        return replacingProofSnapshots(matching: Self.storedSnapshotReference, with: snapshot)
    }

    private var hasStoredSnapshotReference: Bool {
        positions.values.contains { $0.signature?.proof.snapshot == Self.storedSnapshotReference }
    }

    private func replacingProofSnapshots(
        matching original: LeonardoSigningSnapshot,
        with replacement: LeonardoSigningSnapshot
    ) -> Self {
        var result = self
        for (id, progress) in positions {
            guard let signature = progress.signature, signature.proof.snapshot == original else { continue }
            let proof = signature.proof
            let converted = LeonardoSigningProof(
                sessionID: proof.sessionID,
                positionID: proof.positionID,
                profileID: proof.profileID,
                credentialID: proof.credentialID,
                identityDigest: proof.identityDigest,
                snapshot: replacement,
                locationDigests: proof.locationDigests,
                previousSignatureDigest: proof.previousSignatureDigest,
                completionIndex: proof.completionIndex,
                signedAt: proof.signedAt
            )
            result.positions[id]?.signature = LeonardoDetachedSignature(
                proof: converted, signature: signature.signature
            )
        }
        return result
    }
}
