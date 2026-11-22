import Foundation
import LeonardoCore

extension MobileGuidedSigningView {
    func loadProfile(_ id: UUID?) {
        guard let id, let profile = profiles.first(where: { $0.id == id }) else { return }
        fullName = profile.declaredNameForAssignment
        documentType = profile.identity?.documentType ?? .nationalID
        documentNumber = profile.identity?.documentNumber ?? ""
        profileRubric = profile.rubric
    }

    func assignSelectedPosition(_ positionID: String) async {
        busy = true
        defer { busy = false }
        do {
            let profile: LeonardoSignerProfile
            if creatingProfile {
                profile = LeonardoSignerProfile(
                    displayName: fullName,
                    identity: LeonardoDeclaredIdentity(
                        fullName: fullName, documentType: documentType, documentNumber: documentNumber
                    ),
                    rubric: saveRubric ? profileRubric : nil
                )
                if saveIdentityDetails || saveRubric {
                    try await library.signingStore.saveProfile(
                        profile,
                        options: .init(saveIdentityDetails: saveIdentityDetails, saveRubric: saveRubric)
                    )
                    profiles = try await library.signingStore.profiles()
                }
            } else {
                guard let selectedProfileID,
                      let existing = profiles.first(where: { $0.id == selectedProfileID }) else {
                    throw LeonardoSigningError.invalidProfile
                }
                guard let declared = existing.withDeclaredSigningIdentity(.init(
                    fullName: fullName, documentType: documentType, documentNumber: documentNumber
                )) else { throw LeonardoSigningError.invalidProfile }
                profile = declared
            }
            let localTrust = try await library.signingCredentialStore.trustStore(
                credentialIDs: [selectedCredentialID]
            )
            guard let credential = localTrust.credential(id: selectedCredentialID) else {
                throw LeonardoSigningError.unknownCredential(selectedCredentialID)
            }
            let authorization = try LeonardoSigningAuthorization(
                positionID: positionID, profileID: profile.id, credentialID: credential.id,
                confirmedAt: Date(), explicitlyConfirmed: true
            )
            var updated = session
            try updated.assign(positionID: positionID, profile: profile, credential: credential,
                               authorization: authorization, at: Date())
            try await saveProgress(updated)
            // Publish state only after the actor has accepted the CAS write.
            session = updated
            locallyTrustedCredentialIDs.insert(credential.id)
            if !trustedCredentials.contains(where: { $0.id == credential.id }) {
                trustedCredentials.append(credential)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func reportLocationReviewFailure(_ error: Error) {
        switch error as? LeonardoSigningError {
        case .unmappedSigningLocation:
            errorMessage = spanish
                ? "Una rúbrica no coincide con una ubicación exacta en la fuente. Revisa cómo está escrito el campo en el documento original."
                : "A rubric does not match an exact location in the source. Check how the field is written in the original document."
        case .remoteImagesNotSealable:
            errorMessage = spanish
                ? "Sustituye las imágenes en línea por archivos locales en el documento original y vuelve a exportar la copia."
                : "Replace online images with local files in the original document, then export the copy again."
        case .requiredDataMissing(let fields), .requiredDataInvalid(let fields):
            let labels = fields.map { document?.metadata.fields[$0]?.label ?? $0 }.joined(separator: ", ")
            errorMessage = spanish
                ? "Completa o corrige estos campos en el documento original y vuelve a exportar la copia: \(labels)."
                : "Complete or correct these fields in the original document, then export the copy again: \(labels)."
        default:
            errorMessage = error.localizedDescription
        }
    }

    func beginReview(_ positionID: String, document: LeonardoDocument) async {
        busy = true
        defer { busy = false }
        do {
            var updated = session
            _ = try updated.begin(positionID: positionID, document: document, resources: resources)
            try await saveProgress(updated)
            session = updated
        } catch {
            reportLocationReviewFailure(error)
        }
    }

    func pauseReview(_ positionID: String) async {
        busy = true
        defer { busy = false }
        do {
            var updated = session
            try updated.pause(positionID: positionID, at: Date())
            try await saveProgress(updated)
            session = updated
        } catch {
            reportLocationReviewFailure(error)
        }
    }

    func resumeReview(_ positionID: String) async {
        busy = true
        defer { busy = false }
        do {
            var updated = session
            guard let document else { throw LeonardoSigningError.integrityFailure }
            try updated.resume(positionID: positionID, at: Date())
            _ = try updated.begin(positionID: positionID, document: document, resources: resources)
            try await saveProgress(updated)
            session = updated
        } catch {
            reportLocationReviewFailure(error)
        }
    }

    func openDocumentReader() {
        availableTargetKeys = []
        showingDocumentReader = true
    }

    func confirmSelectedTarget(
        reuse: LeonardoRubricReuse,
        rubric: LeonardoRubric,
        reuseConfirmed: Bool = false
    ) {
        guard let document, let selectedPositionID,
              let selectedTargetIndex,
              selectedTargets.indices.contains(selectedTargetIndex) else { return }
        let target = selectedTargets[selectedTargetIndex]
        let targetKey = MobileGuidedSigningTargetKey.make(fieldID: target.fieldID, occurrence: target.occurrence)
        guard availableTargetKeys.contains(targetKey) else {
            errorMessage = spanish
                ? "La aparición no se ha encontrado en el lector; la confirmación se ha bloqueado."
                : "The occurrence was not found in the reader; confirmation was blocked."
            return
        }
        do {
            var updated = session
            try updated.confirmLocation(
                positionID: selectedPositionID, fieldID: target.fieldID, occurrence: target.occurrence,
                document: document, resources: resources, contextRead: true, rubric: rubric,
                reuse: reuse, profileRubric: updated.positions[selectedPositionID]?.assignment?.profileRubric,
                reuseConfirmed: reuseConfirmed, at: Date()
            )
            busy = true
            Task {
                do {
                    try await saveProgress(updated)
                    session = updated
                    busy = false
                }
                catch {
                    reportLocationReviewFailure(error)
                    busy = false
                }
            }
        } catch {
            reportLocationReviewFailure(error)
        }
    }

    func reuseRubric(for reuse: LeonardoRubricReuse) -> LeonardoRubric? {
        guard let selectedPositionID else { return nil }
        switch reuse {
        case .session: return session.rubricByPosition[selectedPositionID]
        case .profile: return session.positions[selectedPositionID]?.assignment?.profileRubric
        case .new: return nil
        }
    }

    func signSelectedPosition(password: String) async {
        guard let document, let selectedPositionID else { return }
        busy = true
        defer { busy = false }
        do {
            let assignment = try requireAssignment(positionID: selectedPositionID)
            let key = try await library.signingCredentialStore.keyPair(
                credentialID: assignment.credentialID, password: password
            )
            let trust = try await library.signingCredentialStore.trustStore()
            var updated = session
            _ = try updated.sign(positionID: selectedPositionID, keyPair: key, document: document,
                                  resources: resources, trustStore: trust, at: Date())
            try await saveProgress(updated)
            session = updated
            updateVerification(trustStore: trust)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func requireAssignment(positionID: String) throws -> LeonardoSigningAssignment {
        guard let assignment = session.positions[positionID]?.assignment else {
            throw LeonardoSigningError.assignmentRequired(positionID)
        }
        return assignment
    }
}
