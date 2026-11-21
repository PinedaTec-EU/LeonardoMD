import CryptoKit
import Foundation
import XCTest
@testable import LeonardoCore

final class LeonardoGuidedSigningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testTargetsFollowDocumentOrderAndRepeatOccurrencesExactly() throws {
        let document = try makeDocument()
        let session = try LeonardoGuidedSigningSession(document: document, at: now)
        let targets = try session.targets(for: "titular", document: document)

        XCTAssertEqual(targets.map { "\($0.fieldID)#\($0.occurrence)" }, ["z#0", "a#0", "a#1"])
        XCTAssertEqual(session.optionalBlankFieldIDs(document: document), ["optionalNote"])
    }

    func testTargetsExcludeEveryMarkdownLiteralFormTheRendererLeavesUntouched() throws {
        var document = try makeDocument()
        document.body = """
        {{field:z}}
        {{field:a}}

        ```text
        {{field:z}}
        ```

            {{field:a}}

        `{{field:a}}`

        <code>{{field:a}}</code>
        <!-- {{field:z}} -->

        ~~~
        {{field:z}}
        """
        let session = try LeonardoGuidedSigningSession(document: document, at: now)
        let targets = try session.targets(for: "titular", document: document)

        XCTAssertEqual(targets.map { "\($0.fieldID)#\($0.occurrence)" }, ["z#0", "a#0"])
    }

    func testTargetsRejectWhenEveryAssignedOccurrenceIsMarkdownLiteral() throws {
        var document = try makeDocument()
        document.body = """
        ```text
        {{field:z}}
        {{field:a}}
        ```
        """
        let session = try LeonardoGuidedSigningSession(document: document, at: now)

        XCTAssertThrowsError(try session.targets(for: "titular", document: document)) { error in
            guard case LeonardoSigningError.fieldNotAssigned = error else {
                return XCTFail("Expected an assigned field with no rendered occurrence to fail closed")
            }
        }
    }

    func testConfirmationMustFollowRenderedSourceOrder() throws {
        let document = try makeDocument(requiredName: "Form complete")
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let ana = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        let anaKey = LeonardoSigningKeyPair(credentialID: "ana")
        try assign(ana, key: anaKey, to: "titular", session: &session)
        _ = try session.begin(positionID: "titular", document: document)

        XCTAssertThrowsError(try session.confirmLocation(
            positionID: "titular", fieldID: "a", occurrence: 0, document: document,
            contextRead: true, rubric: rubric(seed: 1), at: now.addingTimeInterval(1)
        )) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .incompletePosition("titular"))
        }
        XCTAssertEqual(session.positions["titular"]?.locations, [])
        XCTAssertNoThrow(try session.confirmLocation(
            positionID: "titular", fieldID: "z", occurrence: 0, document: document,
            contextRead: true, rubric: rubric(seed: 1), at: now.addingTimeInterval(2)
        ))
    }

    func testFirstConfirmationRequiresCurrentAssignmentAndRequiredData() throws {
        var document = try makeDocument(requiredName: nil)
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let ana = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        let luis = try profile(name: "Luis", number: "L-1", rubric: rubric(seed: 2))
        let anaKey = LeonardoSigningKeyPair(credentialID: "ana")
        let luisKey = LeonardoSigningKeyPair(credentialID: "luis")

        XCTAssertThrowsError(try session.begin(positionID: "titular", document: document)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .assignmentRequired("titular"))
        }
        try assign(ana, key: anaKey, to: "titular", session: &session)
        XCTAssertThrowsError(try session.begin(positionID: "titular", document: document)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .requiredDataMissing(["requiredName"]))
        }

        document.metadata.values["requiredName"] = .string("Form complete")
        XCTAssertNoThrow(try session.begin(positionID: "titular", document: document))
        try session.confirmLocation(
            positionID: "titular", fieldID: "z", document: document,
            contextRead: true, rubric: rubric(seed: 1), at: now.addingTimeInterval(1)
        )
        // The first confirmation freezes the form, but a still-pending
        // position may receive its first assignment afterwards.
        XCTAssertNoThrow(try assign(luis, key: luisKey, to: "testigo", session: &session))
        XCTAssertNoThrow(try session.begin(positionID: "testigo", document: document))
        XCTAssertTrue(session.canSign)
    }

    func testAnaPausesLuisCompletesThenAnaResumesAndChainsSignatures() throws {
        let document = try makeDocument(requiredName: "Form complete")
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let anaRubric = rubric(seed: 1)
        let luisRubric = rubric(seed: 2)
        let ana = try profile(name: "Ana", number: "A-1", rubric: anaRubric)
        let luis = try profile(name: "Luis", number: "L-1", rubric: luisRubric)
        let anaKey = LeonardoSigningKeyPair(credentialID: "ana")
        let luisKey = LeonardoSigningKeyPair(credentialID: "luis")
        try assign(ana, key: anaKey, to: "titular", session: &session)

        _ = try session.begin(positionID: "titular", document: document)
        try session.confirmLocation(
            positionID: "titular", fieldID: "z", document: document,
            contextRead: true, rubric: anaRubric, at: now.addingTimeInterval(1)
        )
        try session.pause(positionID: "titular", at: now.addingTimeInterval(2))
        try assign(luis, key: luisKey, to: "testigo", session: &session)

        _ = try session.begin(positionID: "testigo", document: document)
        let witnessTargets = try session.targets(for: "testigo", document: document)
        try session.confirmLocation(
            positionID: "testigo", fieldID: witnessTargets[0].fieldID,
            occurrence: witnessTargets[0].occurrence, document: document,
            contextRead: true, rubric: luisRubric, at: now.addingTimeInterval(3)
        )
        try session.confirmLocation(
            positionID: "testigo", fieldID: witnessTargets[1].fieldID,
            occurrence: witnessTargets[1].occurrence, document: document,
            contextRead: true, rubric: luisRubric, reuse: .session,
            reuseConfirmed: true, at: now.addingTimeInterval(4)
        )
        XCTAssertEqual(session.positions["testigo"]?.state, .readyToSign)

        let trustStore = try LeonardoSigningTrustRegistry(credentials: [anaKey.credential, luisKey.credential])
        _ = try session.sign(
            positionID: "testigo", keyPair: luisKey, document: document,
            trustStore: trustStore, at: now.addingTimeInterval(5)
        )
        XCTAssertEqual(session.completionOrder, ["testigo"])

        try session.resume(positionID: "titular", at: now.addingTimeInterval(6))
        let titularTargets = try session.targets(for: "titular", document: document)
        for target in titularTargets.dropFirst() {
            try session.confirmLocation(
                positionID: "titular", fieldID: target.fieldID,
                occurrence: target.occurrence, document: document,
                contextRead: true, rubric: anaRubric, reuse: .session,
                reuseConfirmed: true, at: now.addingTimeInterval(7 + Double(target.occurrence))
            )
        }
        XCTAssertEqual(session.positions["titular"]?.state, .readyToSign)
        _ = try session.sign(
            positionID: "titular", keyPair: anaKey, document: document,
            trustStore: trustStore, at: now.addingTimeInterval(10)
        )

        XCTAssertTrue(session.isComplete)
        let results = session.signatureVerification(document: document, trustStore: trustStore)
        XCTAssertEqual(results["titular"], .valid)
        XCTAssertEqual(results["testigo"], .valid)
        XCTAssertNotNil(session.positions["titular"]?.signature?.proof.previousSignatureDigest)

        let originalWitnessSignature = try XCTUnwrap(session.positions["testigo"]?.signature)
        let forgedProof = LeonardoSigningProof(
            sessionID: originalWitnessSignature.proof.sessionID,
            positionID: originalWitnessSignature.proof.positionID,
            profileID: originalWitnessSignature.proof.profileID,
            credentialID: originalWitnessSignature.proof.credentialID,
            identityDigest: originalWitnessSignature.proof.identityDigest,
            snapshot: originalWitnessSignature.proof.snapshot,
            locationDigests: [Data(repeating: 0, count: 32)],
            previousSignatureDigest: originalWitnessSignature.proof.previousSignatureDigest,
            completionIndex: originalWitnessSignature.proof.completionIndex,
            signedAt: originalWitnessSignature.proof.signedAt
        )
        let forgedSignature = LeonardoDetachedSignature(
            proof: forgedProof,
            signature: luisKey.sign(try LeonardoSignatureVerifier.canonicalData(forgedProof))
        )
        var forgedSession = session
        forgedSession.positions["testigo"]?.signature = forgedSignature
        XCTAssertEqual(
            forgedSession.signatureVerification(document: document, trustStore: trustStore)["testigo"],
            .invalidSignature
        )
        XCTAssertEqual(
            forgedSession.signatureVerification(document: document, trustStore: trustStore)["titular"],
            .invalidSignature
        )
    }

    func testRubricReuseIsScopedToPositionAndProfileReuseNeedsConfirmation() throws {
        let document = try makeDocument(requiredName: "Form complete")
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let anaRubric = rubric(seed: 1)
        let luisRubric = rubric(seed: 2)
        let ana = try profile(name: "Ana", number: "A-1", rubric: anaRubric)
        let luis = try profile(name: "Luis", number: "L-1", rubric: luisRubric)
        let anaKey = LeonardoSigningKeyPair(credentialID: "ana")
        let luisKey = LeonardoSigningKeyPair(credentialID: "luis")
        try assign(ana, key: anaKey, to: "titular", session: &session)
        try assign(luis, key: luisKey, to: "testigo", session: &session)
        _ = try session.begin(positionID: "titular", document: document)
        try session.confirmLocation(
            positionID: "titular", fieldID: "z", document: document,
            contextRead: true, rubric: anaRubric, at: now.addingTimeInterval(1)
        )
        _ = try session.begin(positionID: "testigo", document: document)
        XCTAssertThrowsError(try session.confirmLocation(
            positionID: "testigo", fieldID: "witness", document: document,
            contextRead: true, rubric: anaRubric, reuse: .session,
            reuseConfirmed: true, at: now.addingTimeInterval(2)
        )) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .reuseConfirmationRequired)
        }
        let witnessTargets = try session.targets(for: "testigo", document: document)
        XCTAssertThrowsError(try session.confirmLocation(
            positionID: "testigo", fieldID: witnessTargets[0].fieldID,
            occurrence: witnessTargets[0].occurrence, document: document,
            contextRead: true, rubric: luisRubric, reuse: .profile,
            profileRubric: luisRubric, at: now.addingTimeInterval(3)
        )) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .reuseConfirmationRequired)
        }
        try session.confirmLocation(
            positionID: "testigo", fieldID: witnessTargets[0].fieldID,
            occurrence: witnessTargets[0].occurrence, document: document,
            contextRead: true, rubric: luisRubric, reuse: .profile,
            profileRubric: luisRubric, reuseConfirmed: true, at: now.addingTimeInterval(4)
        )
        try session.confirmLocation(
            positionID: "testigo", fieldID: witnessTargets[1].fieldID,
            occurrence: witnessTargets[1].occurrence, document: document,
            contextRead: true, rubric: luisRubric, reuse: .session,
            reuseConfirmed: true, at: now.addingTimeInterval(5)
        )
        XCTAssertEqual(session.positions["testigo"]?.state, .readyToSign)
    }

    func testAssignmentsCannotChangeAfterFirstConfirmationAndSnapshotRejectsMutation() throws {
        let resource = LeonardoSigningResource(reference: "assets/evidence.txt", bytes: Data("one".utf8))
        var document = try makeDocument(requiredName: "Form complete")
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let ana = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        let anaKey = LeonardoSigningKeyPair(credentialID: "ana")
        try assign(ana, key: anaKey, to: "titular", session: &session)
        _ = try session.begin(positionID: "titular", document: document)
        try session.confirmLocation(
            positionID: "titular", fieldID: "z", document: document,
            resources: [resource], contextRead: true, rubric: rubric(seed: 1), at: now
        )
        let replacement = try profile(name: "Replacement", number: "R-1", rubric: rubric(seed: 3))
        let replacementKey = LeonardoSigningKeyPair(credentialID: "replacement")
        XCTAssertNoThrow(try assign(replacement, key: replacementKey, to: "testigo", session: &session))
        XCTAssertThrowsError(try assign(ana, key: anaKey, to: "titular", session: &session)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .assignmentsLocked)
        }
        document.metadata.values["optionalNote"] = .string("changed")
        XCTAssertThrowsError(try session.confirmLocation(
            positionID: "titular", fieldID: "a", occurrence: 0, document: document,
            resources: [resource], contextRead: true, rubric: rubric(seed: 1),
            reuse: .session, reuseConfirmed: true, at: now.addingTimeInterval(1)
        )) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .integrityFailure)
        }
        XCTAssertEqual(session.state, .invalidated)
    }

    func testDocumentCorrectionStartsFreshSessionAndCommitmentSaltIsRandom() throws {
        let document = try makeDocument(requiredName: "Form complete")
        let first = try LeonardoGuidedSigningSession(document: document, at: now)
        let second = try LeonardoGuidedSigningSession(document: document, at: now)
        XCTAssertNotEqual(first.identityCommitmentSalt, second.identityCommitmentSalt)

        var changed = document
        changed.metadata.document.revision = 2
        changed.body += "\nCorrection"
        XCTAssertThrowsError(try first.correctedSession(document: document, at: now))
        let corrected = try first.correctedSession(document: changed, at: now.addingTimeInterval(1))
        XCTAssertTrue(corrected.completionOrder.isEmpty)
        XCTAssertTrue(corrected.pendingPositionIDs.allSatisfy { corrected.positions[$0]?.signature == nil })
    }

    func testOfflineSigningExchangeRoundTripsAndRejectsChangedAuthoritativeSource() throws {
        let document = try makeDocument(requiredName: "Form complete")
        var session = try LeonardoGuidedSigningSession(
            document: document, at: now, documentLocation: "/Users/example/private.mdlf"
        )
        let signer = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        let key = LeonardoSigningKeyPair(credentialID: "ana")
        try assign(signer, key: key, to: "titular", session: &session)
        _ = try session.begin(positionID: "titular", document: document)
        let targets = try session.targets(for: "titular", document: document)
        for (index, target) in targets.enumerated() {
            try session.confirmLocation(
                positionID: "titular", fieldID: target.fieldID, occurrence: target.occurrence,
                document: document, contextRead: true,
                rubric: rubric(seed: index + 1), at: now.addingTimeInterval(Double(index + 1))
            )
        }
        let trust = try LeonardoSigningTrustRegistry(credentials: [key.credential])
        _ = try session.sign(
            positionID: "titular", keyPair: key, document: document,
            trustStore: trust, at: now.addingTimeInterval(10)
        )

        let resource = LeonardoSigningResource(reference: "assets/evidence.txt", bytes: Data("evidence".utf8))
        // The resource is intentionally not in the snapshot, so an exchange
        // must carry exactly the same resource set as its session snapshot.
        XCTAssertThrowsError(try LeonardoSigningExchange(
            document: document, resources: [resource], session: session,
            trustedCredentials: [key.credential], at: now
        ))

        let exchange = try LeonardoSigningExchange(
            document: document, session: session,
            trustedCredentials: [key.credential], at: now.addingTimeInterval(0.123456789)
        )
        let encoded = try LeonardoSigningExchange.encoded(exchange)
        let decoded = try LeonardoSigningExchange.decoded(encoded)
        XCTAssertEqual(decoded, exchange)
        XCTAssertNil(decoded.session.documentLocation)
        XCTAssertEqual(try decoded.document(), document)
        XCTAssertEqual(decoded.trustedCredentials, [key.credential])
        try decoded.validate(against: document, trustStore: trust)
        let rebound = try decoded.reboundSession(onto: nil, documentLocation: "/Users/example/private.mdlf")
        XCTAssertEqual(rebound.documentLocation, "/Users/example/private.mdlf")
        XCTAssertEqual(
            try decoded.reboundSession(onto: rebound, documentLocation: "/Users/example/private.mdlf"),
            rebound
        )

        var changed = document
        changed.metadata.values["requiredName"] = .string("Changed elsewhere")
        XCTAssertThrowsError(try decoded.validate(against: changed, trustStore: trust)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .integrityFailure)
        }
    }

    func testProfileIdentityDocumentAndCredentialCannotBeReused() throws {
        let document = try makeDocument(requiredName: "Form complete")
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let ana = try profile(name: "Ana", number: "SAME", rubric: rubric(seed: 1))
        let anotherNameSameDocument = try profile(name: "Other", number: "SAME", rubric: rubric(seed: 2))
        let sameProfileDifferentIdentity = LeonardoSignerProfile(
            id: ana.id, displayName: "Ana", identity: LeonardoDeclaredIdentity(
                fullName: "Ana", documentType: .nationalID, documentNumber: "OTHER"
            ), rubric: rubric(seed: 3)
        )
        let firstKey = LeonardoSigningKeyPair(credentialID: "first")
        let secondKey = LeonardoSigningKeyPair(credentialID: "second")
        try assign(ana, key: firstKey, to: "titular", session: &session)

        XCTAssertThrowsError(try assign(anotherNameSameDocument, key: secondKey, to: "testigo", session: &session)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .identityDocumentReused)
        }
        XCTAssertThrowsError(try assign(sameProfileDifferentIdentity, key: secondKey, to: "testigo", session: &session)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .profileReused)
        }
        let differentProfile = try profile(name: "Other", number: "OTHER", rubric: rubric(seed: 4))
        let sameCredential = LeonardoSigningKeyPair(credentialID: "first")
        XCTAssertThrowsError(try assign(differentProfile, key: sameCredential, to: "testigo", session: &session)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .credentialReused)
        }
    }

    func testStoreUsesConsentAndRejectsStaleSessionWithoutErasingProgress() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeA = LeonardoSigningStore(directoryURL: directory)
        let storeB = LeonardoSigningStore(directoryURL: directory)
        let profile = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        try await storeA.saveProfile(profile, options: .init(saveIdentityDetails: false, saveRubric: false))
        let storedProfiles = try await storeA.profiles()
        let saved = try XCTUnwrap(storedProfiles.first)
        XCTAssertEqual(saved.displayName, "Local signer")
        XCTAssertNil(saved.identity)
        XCTAssertNil(saved.rubric)

        let document = try makeDocument(requiredName: "Form complete")
        let session = try LeonardoGuidedSigningSession(document: document, at: now)
        try await storeA.saveSession(session)
        let staleValue = try await storeB.session(id: session.id)
        let stale = try XCTUnwrap(staleValue)
        var newer = session
        newer.updatedAt = now.addingTimeInterval(1)
        try await storeA.saveSession(newer)
        do {
            try await storeB.saveSession(stale)
            XCTFail("A stale session must not overwrite the newer progress")
        } catch let error as LeonardoSigningError {
            XCTAssertEqual(error, .staleStorage)
        }
        let file = directory.appendingPathComponent("signing-progress.json")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    private func assign(
        _ profile: LeonardoSignerProfile,
        key: LeonardoSigningKeyPair,
        to positionID: String,
        session: inout LeonardoGuidedSigningSession
    ) throws {
        let authorization = try LeonardoSigningAuthorization(
            positionID: positionID,
            profileID: profile.id,
            credentialID: key.credential.id,
            confirmedAt: now,
            explicitlyConfirmed: true
        )
        try session.assign(
            positionID: positionID,
            profile: profile,
            credential: key.credential,
            authorization: authorization,
            at: now
        )
    }

    private func profile(
        name: String,
        number: String,
        rubric: LeonardoRubric
    ) throws -> LeonardoSignerProfile {
        LeonardoSignerProfile(
            displayName: name,
            identity: LeonardoDeclaredIdentity(
                fullName: name,
                documentType: .nationalID,
                documentNumber: number
            ),
            rubric: rubric
        )
    }

    private func rubric(seed: Int) -> LeonardoRubric {
        LeonardoRubric(strokes: [LeonardoInkStroke(
            color: "#000000",
            width: 2,
            style: .solid,
            points: [LeonardoInkPoint(x: Double(seed), y: 10), LeonardoInkPoint(x: Double(seed + 1), y: 11)]
        )])
    }

    private func makeDocument(requiredName: String? = "Form complete") throws -> LeonardoDocument {
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "titular", label: "Titular"),
            LeonardoSignerPosition(id: "testigo", label: "Testigo")
        ])
        let metadata = LeonardoMetadata(
            formatVersion: LeonardoFormat.signingVersion,
            document: LeonardoDocumentDescriptor(
                id: "guided-form",
                title: "Guided form",
                kind: .form,
                revision: 1,
                signing: declaration
            ),
            fields: [
                "z": LeonardoFieldDefinition(type: .rubric, signerPosition: "titular"),
                "a": LeonardoFieldDefinition(type: .rubric, signerPosition: "titular"),
                "witness": LeonardoFieldDefinition(type: .rubric, signerPosition: "testigo"),
                "requiredName": LeonardoFieldDefinition(type: .text, required: true),
                "optionalNote": LeonardoFieldDefinition(type: .text)
            ],
            values: [
                "requiredName": requiredName.map(LeonardoJSONValue.string) ?? .null,
                "optionalNote": .null
            ]
        )
        return LeonardoDocument(
            body: "{{field:z}}\n{{field:a}} {{field:a}}\n{{field:witness}} {{field:witness}}",
            metadata: metadata
        )
    }
}
