import AppKit
import CryptoKit
import Darwin
import Foundation
import LeonardoCore
import LeonardoSync
import UniformTypeIdentifiers

extension AppSession {
    /// Corrections are explicit and advance the semantic revision. The old
    /// sidecar session remains an audit record; the fresh one starts empty.
    func startGuidedSigningRevision() async {
        guard let previous = guidedSigningSession, let document = leonardoDocument,
              let expectedLocation = guidedSigningLocation else { return }
        let expectedContent = content
        do {
            guard !isProtected, !stopped, !isClosing, !isSyncSuspended, !busy,
                  !saving, fileOperationCount == 0, !isCapturingPreview,
                  guidedSigningRevisionViewStateMatches(
                      expectedLocation: expectedLocation,
                      expectedContent: expectedContent,
                      expectedSession: previous
                  ) else {
                guidedSigningError = L10n.text("The new revision could not be opened for editing.")
                return
            }
            let source = try await guidedSigningRevisionSource(for: previous, current: document)
            guard let baseRevision = source.document.metadata.document.revision,
                  baseRevision >= 1 else {
                throw LeonardoSigningError.integrityFailure
            }
            let history = try await guidedSigningStore.sessions()
            guard guidedSigningRevisionViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: previous
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            let historicalMaximum = history
                .filter {
                    $0.documentLocation == expectedLocation
                        && $0.documentID == previous.documentID
                }
                .compactMap(\.initialRevision)
                .max() ?? baseRevision
            let latestRevision = max(baseRevision, historicalMaximum)
            guard latestRevision < Int.max else { throw LeonardoSigningError.storageFailure }
            var nextRevision = latestRevision + 1
            var committed: (replacement: String, session: LeonardoGuidedSigningSession)?
            // Save the new sidecar before changing the editor. A racing
            // session at the same path/ID/revision advances to the next free
            // monotonic revision; all other failures leave the old source and
            // session untouched.
            for _ in 0..<32 {
                var revised = source.document
                revised.metadata.document.revision = nextRevision
                let replacement = try LeonardoFormatParser.serialize(revised)
                let fresh = try previous.correctedSession(
                    document: revised,
                    resources: source.resources,
                    at: Date(),
                    documentLocation: expectedLocation
                )
                do {
                    try await guidedSigningStore.saveSession(fresh, replacing: nil)
                    committed = (replacement, fresh)
                    break
                } catch let error as LeonardoSigningError where error == .staleStorage {
                    guard nextRevision < Int.max else { throw LeonardoSigningError.storageFailure }
                    nextRevision += 1
                }
            }
            guard let committed else { throw LeonardoSigningError.staleStorage }

            guard guidedSigningRevisionViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: previous
            ) else {
                throw LeonardoSigningError.integrityFailure
            }

            // `editDocument` is synchronous. The temporary flag opens the
            // editor only for this exact replacement; no ordinary edit can
            // interleave while it is set.
            guidedSigningRevisionEditing = true
            let edited = editDocument(expected: expectedContent, replacement: committed.replacement)
            guidedSigningRevisionEditing = false
            guard edited else {
                guidedSigningError = L10n.text("The new revision could not be opened for editing.")
                return
            }
            guard guidedSigningLocation == expectedLocation,
                  content == committed.replacement,
                  guidedSigningSession == previous else {
                guidedSigningError = L10n.text("The document moved or changed while creating the new revision. Reload it before continuing.")
                return
            }
            // Do not let Undo restore the sealed source while this fresh
            // sidecar revision is active.
            editHistory = DocumentEditHistory()
            guidedSigningSession = committed.session
            guidedSigningRecoveryBlocked = false
            if source.recovered {
                externalConflict = true
                saveStatus = "External conflict · signing review protected"
                guidedSigningReady = true
            }
            refreshGuidedSigningTargets()
            guidedSigningStatus = source.recovered
                ? L10n.text("Trusted revision recovered. Save a copy before signing.")
                : L10n.text("New revision ready. Review and assign every signer again.")
            guidedSigningError = nil
        } catch {
            guidedSigningRevisionEditing = false
            let blocksRecovery: Bool
            if let signingError = error as? LeonardoSigningError {
                switch signingError {
                case .integrityFailure, .trustStoreRequired, .invalidResourceReference, .resourceTooLarge:
                    blocksRecovery = true
                default:
                    blocksRecovery = false
                }
            } else {
                blocksRecovery = false
            }
            if blocksRecovery {
                guidedSigningRecoveryBlocked = true
                guidedSigningError = guidedSigningRecoveryBlockedMessage()
            } else {
                guidedSigningError = String(describing: error)
            }
        }
    }
}
