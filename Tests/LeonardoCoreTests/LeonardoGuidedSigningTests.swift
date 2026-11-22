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

    func testNestedAndContinuedRubricsMustBothBeReviewedBeforeSigning() throws {
        var document = try makeDocument()
        document.body = """
        - Checklist
            - Nested signature {{field:a}}

        Continuation
            Continued signature {{field:a}}

            Literal code {{field:a}}

        > `Quoted literal {{field:a}}`

        Use `<code>` for a literal example.

        Last signature {{field:z}}
        """
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let signer = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        let key = LeonardoSigningKeyPair(credentialID: "ana")
        try assign(signer, key: key, to: "titular", session: &session)
        let targets = try session.begin(positionID: "titular", document: document)
        XCTAssertEqual(targets.map { "\($0.fieldID)#\($0.occurrence)" }, ["a#0", "a#1", "z#0"])
        for (target, precedingText) in zip(targets, ["Nested signature ", "Continued signature ", "Last signature "]) {
            let source = try XCTUnwrap(document.body.range(of: precedingText))
            XCTAssertEqual(target.sourceOffset, document.body.distance(from: document.body.startIndex, to: source.upperBound))
        }

        let trust = try LeonardoSigningTrustRegistry(credentials: [key.credential])
        for (index, target) in targets.enumerated() {
            if index > 0 {
                XCTAssertThrowsError(try session.sign(
                    positionID: "titular", keyPair: key, document: document, trustStore: trust, at: now
                ))
            }
            try session.confirmLocation(
                positionID: "titular", fieldID: target.fieldID, occurrence: target.occurrence,
                document: document, contextRead: true, rubric: rubric(seed: index + 1), at: now
            )
        }
        let completed = try session.sign(
            positionID: "titular", keyPair: key, document: document, trustStore: trust, at: now
        )
        XCTAssertEqual(completed.proof.locationDigests.count, 3)
    }

    func testGuidedOccurrencesMustCorrespondToLiteralSourceTokens() throws {
        var document = try makeDocument()
        document.body = "{{field:z}} {{field:a}} &#123;&#123;field:a}}"
        let session = try LeonardoGuidedSigningSession(document: document, at: now)
        XCTAssertThrowsError(try session.targets(for: "titular", document: document)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .unmappedSigningLocation)
        }
    }

    func testLiveImagesBlockTheSigningSealButLiteralLinksDoNot() throws {
        let signer = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        let key = LeonardoSigningKeyPair(credentialID: "ana")
        for image in [
            "![Live](https://example.invalid/image.png)",
            #"<img src="//example.invalid/image.png" alt="Live">"#,
            #"<img src="local.png" srcset="https://example.invalid/image.png 2x">"#,
            "![Live][image]\n\n[image]: http://example.invalid/image.png"
        ] {
            var document = try makeDocument()
            document.body += "\n\n" + image
            var session = try LeonardoGuidedSigningSession(document: document, at: now)
            try assign(signer, key: key, to: "titular", session: &session)
            XCTAssertThrowsError(try session.begin(positionID: "titular", document: document)) { error in
                XCTAssertEqual(error as? LeonardoSigningError, .remoteImagesNotSealable)
            }
            XCTAssertNil(session.snapshot)
            XCTAssertTrue(try XCTUnwrap(session.positions["titular"]).locations.isEmpty)
        }

        var document = try makeDocument()
        document.body += "\n\n[Ordinary link](https://example.invalid/image.png) `![Example](https://example.invalid/image.png)`\n\n    ![Literal](https://example.invalid/image.png)"
        XCTAssertNoThrow(try LeonardoSigningSnapshot.capture(document: document, at: now))
        document.metadata.layout = LeonardoLayout(background: .init(image: "https://example.invalid/background.png"))
        XCTAssertThrowsError(try LeonardoSigningSnapshot.capture(document: document, at: now)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .remoteImagesNotSealable)
        }
    }

    func testSigningImagePathsDecodeHTMLReferencesAndRecognizeEmbeddedImages() throws {
        var document = try makeDocument()
        document.body += "\n\n" + #"<img src="a&amp;b.png" srcset="caf&eacute;.png 1x, a&amp;b.png 2x">"#
        XCTAssertEqual(try LeonardoLocalImagePolicy.signingReferences(in: document), ["a&b.png", "café.png"])
        XCTAssertFalse(try LeonardoLocalImagePolicy.hasEmbeddedSigningImages(in: document))
        document.body += "\n\n![Embedded](data:image/png;base64,AAAA)"
        XCTAssertTrue(try LeonardoLocalImagePolicy.hasEmbeddedSigningImages(in: document))
        XCTAssertEqual(try LeonardoLocalImagePolicy.signingReferences(in: document), ["a&b.png", "café.png"])
    }

    func testResponsiveImageMutationInvalidatesTheSealAndMissingCandidatesBlockIt() throws {
        var document = try makeDocument()
        let image = #"<picture><source srcset="better.png 2x, middle.png 1x"><img src="fallback.png"></picture>"#
        document.body += "\n\n" + image
        XCTAssertEqual(Set(try LeonardoLocalImagePolicy.signingReferences(in: document)), [
            "better.png", "middle.png", "fallback.png"
        ])
        let fallback = LeonardoSigningResource(reference: "fallback.png", bytes: Data([1]))
        let middle = LeonardoSigningResource(reference: "middle.png", bytes: Data([2]))
        let better = LeonardoSigningResource(reference: "better.png", bytes: Data([3]))
        XCTAssertThrowsError(try LeonardoSigningSnapshot.capture(
            document: document, resources: [fallback, middle], at: now
        )) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .invalidResourceReference("better.png"))
        }

        let snapshot = try LeonardoSigningSnapshot.capture(
            document: document, resources: [fallback, middle, better], at: now
        )
        XCTAssertTrue(snapshot.matches(document: document, resources: [fallback, middle, better]))
        let edited = LeonardoSigningResource(reference: "better.png", bytes: Data([4]))
        XCTAssertFalse(snapshot.matches(document: document, resources: [fallback, middle, edited]))

        document.body = document.body.replacingOccurrences(of: "better.png", with: "https://example.invalid/better.png")
        XCTAssertThrowsError(try LeonardoSigningSnapshot.capture(
            document: document, resources: [fallback, middle, better], at: now
        )) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .remoteImagesNotSealable)
        }
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

    func testUnassignedRubricsUseOrdinaryRequiredAndOptionalDataValidation() throws {
        var document = try makeDocument(requiredName: "Form complete")
        document.metadata.fields["requiredRubric"] = LeonardoFieldDefinition(
            type: .rubric, required: true
        )
        document.metadata.fields["optionalRubric"] = LeonardoFieldDefinition(type: .rubric)
        document.metadata.values["requiredRubric"] = .null
        document.metadata.values["optionalRubric"] = .null

        let session = try LeonardoGuidedSigningSession(document: document, at: now)
        XCTAssertEqual(
            session.optionalBlankFieldIDs(document: document),
            ["optionalNote", "optionalRubric"]
        )

        var assignedSession = session
        let signer = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        let key = LeonardoSigningKeyPair(credentialID: "ana")
        try assign(signer, key: key, to: "titular", session: &assignedSession)
        XCTAssertThrowsError(try assignedSession.begin(positionID: "titular", document: document)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .requiredDataMissing(["requiredRubric"]))
        }

        document.metadata.values["requiredRubric"] = try XCTUnwrap(rubric(seed: 9).jsonValue)
        XCTAssertNoThrow(try assignedSession.begin(positionID: "titular", document: document))
    }

    func testInvalidRequiredValuesStayEditableUntilTheyAreCorrected() throws {
        var document = try makeDocument(requiredName: "Form complete")
        document.metadata.fields["amount"] = .init(type: .number, required: true, minimum: 10)
        document.metadata.fields["email"] = .init(type: .email, required: true)
        document.metadata.values["amount"] = .number(2)
        document.metadata.values["email"] = .string("invalid")
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let key = LeonardoSigningKeyPair(credentialID: "ana")
        try assign(profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1)),
                   key: key, to: "titular", session: &session)

        XCTAssertThrowsError(try session.begin(positionID: "titular", document: document)) {
            XCTAssertEqual($0 as? LeonardoSigningError, .requiredDataInvalid(["amount", "email"]))
        }
        XCTAssertNil(session.snapshot)

        document.metadata.values["amount"] = .number(10)
        document.metadata.values["email"] = .string("ana@example.com")
        _ = try session.begin(positionID: "titular", document: document)
        document.metadata.values["email"] = .string("invalid")
        XCTAssertThrowsError(try session.confirmLocation(
            positionID: "titular", fieldID: "z", document: document,
            contextRead: true, rubric: rubric(seed: 1), at: now
        )) {
            XCTAssertEqual($0 as? LeonardoSigningError, .requiredDataInvalid(["email"]))
        }
        XCTAssertNil(session.snapshot)
        document.metadata.values["email"] = .string("ana@example.com")
        try session.confirmLocation(positionID: "titular", fieldID: "z", document: document,
                                    contextRead: true, rubric: rubric(seed: 1), at: now)
        XCTAssertNotNil(session.snapshot)
    }

    func testResumingAfterPausingAtLastLocationRestoresReadyToSign() throws {
        let document = try makeDocument(requiredName: "Form complete")
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let signerRubric = rubric(seed: 1)
        let signer = try profile(name: "Ana", number: "A-1", rubric: signerRubric)
        let key = LeonardoSigningKeyPair(credentialID: "ana")
        try assign(signer, key: key, to: "titular", session: &session)

        let targets = try session.begin(positionID: "titular", document: document)
        for (index, target) in targets.enumerated() {
            try session.confirmLocation(
                positionID: "titular", fieldID: target.fieldID, occurrence: target.occurrence,
                document: document, contextRead: true,
                rubric: signerRubric,
                reuse: index == 0 ? .new : .session,
                reuseConfirmed: index > 0,
                at: now.addingTimeInterval(Double(index + 1))
            )
        }
        XCTAssertEqual(session.positions["titular"]?.state, .readyToSign)

        try session.pause(positionID: "titular", at: now.addingTimeInterval(10))
        XCTAssertEqual(session.positions["titular"]?.state, .paused)
        try session.resume(positionID: "titular", at: now.addingTimeInterval(11))
        XCTAssertEqual(session.positions["titular"]?.state, .reviewing)
        _ = try session.begin(positionID: "titular", document: document)
        XCTAssertEqual(session.positions["titular"]?.state, .readyToSign)
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

    func testSigningCopyCannotClaimExternalIdentityVerification() throws {
        let document = try makeDocument(requiredName: "Complete")
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let key = LeonardoSigningKeyPair(credentialID: "ana")
        let declaration = LeonardoDeclaredIdentity(fullName: "Ana Example", documentType: .nationalID, documentNumber: "A-1")
        let profile = LeonardoSignerProfile(displayName: "Ana", identity: declaration, verificationStatus: .independentlyVerified)
        try assign(profile, key: key, to: "titular", session: &session)
        XCTAssertEqual(session.positions["titular"]?.assignment?.identityStatus, .declared)

        let targets = try session.begin(positionID: "titular", document: document)
        for (index, target) in targets.enumerated() {
            try session.confirmLocation(positionID: target.positionID, fieldID: target.fieldID,
                                        occurrence: target.occurrence, document: document,
                                        contextRead: true, rubric: rubric(seed: index + 1), at: now)
        }
        let trust = try LeonardoSigningTrustRegistry(credentials: [key.credential])
        _ = try session.sign(positionID: "titular", keyPair: key, document: document, trustStore: trust, at: now)
        let exchange = try LeonardoSigningExchange(document: document, session: session,
                                                    trustedCredentials: [key.credential], at: now)
        try exchange.validate(against: document, trustStore: trust)
        let encoded = try LeonardoSigningExchange.encoded(exchange)
        var copy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var encodedSession = try XCTUnwrap(copy["session"] as? [String: Any])
        var positions = try XCTUnwrap(encodedSession["positions"] as? [String: Any])
        var position = try XCTUnwrap(positions["titular"] as? [String: Any])
        var assignment = try XCTUnwrap(position["assignment"] as? [String: Any])
        assignment["identityStatus"] = "independentlyVerified"
        position["assignment"] = assignment
        positions["titular"] = position
        encodedSession["positions"] = positions
        copy["session"] = encodedSession

        XCTAssertThrowsError(try LeonardoSigningExchange.decoded(JSONSerialization.data(withJSONObject: copy))) {
            XCTAssertEqual($0 as? LeonardoSigningError, .integrityFailure)
        }
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

        let compacted = try session.compactingProofSnapshotsForStorage()
        XCTAssertEqual(compacted.snapshot, session.snapshot)
        XCTAssertTrue(try XCTUnwrap(compacted.positions["titular"]?.signature).proof.snapshot.source.isEmpty)
        XCTAssertEqual(try compacted.restoringProofSnapshotsFromStorage(), session)
        XCTAssertThrowsError(try compacted.compactingProofSnapshotsForStorage())

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

    func testExchangeValidatesPartialProgressAgainstTheSealedDocument() throws {
        let document = try makeDocument()
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let key = LeonardoSigningKeyPair(credentialID: "partial")
        try assign(profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1)),
                   key: key, to: "titular", session: &session)
        let target = try XCTUnwrap(session.begin(positionID: "titular", document: document).first)
        try session.confirmLocation(
            positionID: "titular", fieldID: target.fieldID, occurrence: target.occurrence,
            document: document, contextRead: true, rubric: rubric(seed: 1), at: now
        )
        try session.pause(positionID: "titular", at: now)
        let trust = try LeonardoSigningTrustRegistry(credentials: [key.credential])
        let exchange = try LeonardoSigningExchange(
            document: document, session: session, trustedCredentials: [key.credential], at: now
        )
        let accepted = try LeonardoSigningExchange.decoded(LeonardoSigningExchange.encoded(exchange))
        try accepted.validate(against: document, trustStore: trust)
        let baseline = try accepted.reboundSession(onto: nil, documentLocation: "/fixture.mdlf")
        XCTAssertEqual(baseline.positions["titular"]?.state, .paused)

        var withoutSeal = session
        withoutSeal.snapshot = nil
        XCTAssertThrowsError(try withoutSeal.validateExchangeProgress(document: document, resources: []))

        var wrongLocation = session
        let confirmed = try XCTUnwrap(wrongLocation.positions["titular"]?.locations.first)
        wrongLocation.positions["titular"]?.locations = [.init(
            positionID: confirmed.positionID, fieldID: confirmed.fieldID, occurrence: confirmed.occurrence,
            sourceOffset: confirmed.sourceOffset + 1, contextSHA256: confirmed.contextSHA256,
            rubric: confirmed.rubric, reuse: confirmed.reuse, confirmedAt: confirmed.confirmedAt
        )]
        XCTAssertThrowsError(try wrongLocation.validateExchangeProgress(document: document, resources: []))

        var withoutAssignment = session
        withoutAssignment.positions["titular"]?.assignment = nil
        XCTAssertThrowsError(try withoutAssignment.validateExchangeProgress(document: document, resources: []))

        let incomplete = try makeDocument(requiredName: nil)
        var incompleteSeal = session
        incompleteSeal.snapshot = try LeonardoSigningSnapshot.capture(document: incomplete, resources: [], at: now)
        XCTAssertThrowsError(try incompleteSeal.validateExchangeProgress(document: incomplete, resources: [])) {
            XCTAssertEqual($0 as? LeonardoSigningError, .requiredDataMissing(["requiredName"]))
        }
        var resumed = baseline
        try resumed.resume(positionID: "titular", at: now)
        XCTAssertEqual(try resumed.begin(positionID: "titular", document: document).first, target)
    }

    func testSigningExchangeRejectsResourcesThatExceedEncodedEnvelopeLimit() throws {
        let document = try makeDocument()
        let session = try LeonardoGuidedSigningSession(document: document, at: now)
        let boundaryBytes = 15 * 1_024 * 1_024 / 2
        let largeResource = Data(repeating: 0x41, count: boundaryBytes)

        func exchange(lastBytes: Data) throws -> LeonardoSigningExchange {
            let resources = (0..<4).map { index in
                LeonardoSigningResource(
                    reference: "assets/image-\(index).png",
                    bytes: index == 3 ? lastBytes : largeResource
                )
            }
            return try LeonardoSigningExchange(
                document: document, resources: resources, session: session,
                trustedCredentials: [], at: now
            )
        }

        let fits = try exchange(lastBytes: largeResource.dropLast(16 * 1_024))
        XCTAssertEqual(try LeonardoSigningExchange.decoded(LeonardoSigningExchange.encoded(fits)), fits)

        let oversized = try exchange(lastBytes: largeResource)
        XCTAssertThrowsError(try LeonardoSigningExchange.encoded(oversized)) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .exchangeTooLarge)
        }

        let rawLimitExceeded = (0..<5).map { index in
            LeonardoSigningResource(reference: "assets/large-\(index).png", bytes: largeResource)
        }
        XCTAssertThrowsError(try LeonardoSigningExchange(
            document: document, resources: rawLimitExceeded, session: session,
            trustedCredentials: [], at: now
        )) { error in
            XCTAssertEqual(error as? LeonardoSigningError, .exchangeTooLarge)
        }
    }

    func testSigningExchangeCarriesOnlyParticipatingCredentials() throws {
        let document = try makeDocument(requiredName: "Form complete")
        let unrelated = LeonardoSigningKeyPair(credentialID: "unrelated")
        let emptySession = try LeonardoGuidedSigningSession(document: document, at: now)

        let pristine = try LeonardoSigningExchange(
            document: document,
            session: emptySession,
            trustedCredentials: [unrelated.credential],
            at: now
        )
        XCTAssertTrue(pristine.trustedCredentials.isEmpty)

        let incomingPristine = try injectCredential(unrelated.credential, into: pristine)
        XCTAssertTrue(try LeonardoSigningExchange.decoded(incomingPristine).trustedCredentials.isEmpty)

        var assignedSession = emptySession
        let participating = LeonardoSigningKeyPair(credentialID: "participating")
        let signer = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        try assign(signer, key: participating, to: "titular", session: &assignedSession)
        let assigned = try LeonardoSigningExchange(
            document: document,
            session: assignedSession,
            trustedCredentials: [participating.credential, unrelated.credential],
            at: now
        )
        XCTAssertEqual(assigned.trustedCredentials.map(\.id), [participating.credential.id])

        let incomingAssigned = try injectCredential(unrelated.credential, into: assigned)
        let decoded = try LeonardoSigningExchange.decoded(incomingAssigned)
        XCTAssertEqual(decoded.trustedCredentials.map(\.id), [participating.credential.id])
    }

    private func injectCredential(
        _ credential: LeonardoSigningCredential,
        into exchange: LeonardoSigningExchange
    ) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: LeonardoSigningExchange.encoded(exchange))
                as? [String: Any]
        )
        var credentials = try XCTUnwrap(object["trustedCredentials"] as? [[String: Any]])
        credentials.append([
            "id": credential.id,
            "publicKey": credential.publicKey.base64EncodedString()
        ])
        object["trustedCredentials"] = credentials
        return try JSONSerialization.data(withJSONObject: object)
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

    func testStoreReplacesOnlyPristineLocalSessionForImportedCopy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LeonardoSigningStore(directoryURL: directory)
        let document = try makeDocument(requiredName: "Form complete")
        let location = "/Users/example/private.mdlf"
        let local = try LeonardoGuidedSigningSession(document: document, at: now,
                                                     documentLocation: location)
        let imported = try LeonardoGuidedSigningSession(document: document,
                                                        at: now.addingTimeInterval(1),
                                                        documentLocation: location)
        XCTAssertTrue(local.isPristine)
        XCTAssertTrue(imported.isPristine)
        try await store.saveSession(local)
        try await store.replacePristineSession(id: local.id, with: imported)
        let removedLocal = try await store.session(id: local.id)
        let storedImported = try await store.session(id: imported.id)
        XCTAssertNil(removedLocal)
        XCTAssertEqual(storedImported?.documentLocation, location)

        var assigned = try LeonardoGuidedSigningSession(document: document, at: now,
                                                        documentLocation: location)
        let signer = try profile(name: "Ana", number: "A-1", rubric: rubric(seed: 1))
        let key = LeonardoSigningKeyPair(credentialID: "ana")
        try assign(signer, key: key, to: "titular", session: &assigned)
        XCTAssertFalse(assigned.isPristine)
        let competing = try LeonardoGuidedSigningSession(document: document,
                                                          at: now.addingTimeInterval(2))
        try await store.removeSession(id: imported.id)
        try await store.saveSession(assigned)
        do {
            try await store.replacePristineSession(id: assigned.id, with: competing)
            XCTFail("A session with an assignment must not be replaced")
        } catch let error as LeonardoSigningError {
            XCTAssertEqual(error, .staleStorage)
        }
        let retainedAssigned = try await store.session(id: assigned.id)
        XCTAssertEqual(retainedAssigned, assigned)
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
