import Foundation
import LeonardoCore

extension MobileGuidedSigningView {
    func loadLocalSigningData() async {
        ready = false
        localLoadFailed = false
        do {
            profiles = try await library.signingStore.profiles()
            credentialIDs = try await library.signingCredentialStore.credentialIDs()
            let localTrust = try await library.signingCredentialStore.trustStore()
            locallyTrustedCredentialIDs = Set(trustedCredentials.compactMap { packageCredential in
                localTrust.credential(id: packageCredential.id) == packageCredential ? packageCredential.id : nil
            })
            selectedTrustCredentialID = untrustedPackageCredentials.first?.id
            trustAccepted = untrustedPackageCredentials.isEmpty
            try await restoreProgress(trustStore: localTrust)
            locallyTrustedCredentialIDs = Set(trustedCredentials.compactMap { credential in
                localTrust.credential(id: credential.id) == credential ? credential.id : nil
            })
            trustAccepted = untrustedPackageCredentials.isEmpty
            updateVerification(trustStore: localTrust)
            ready = true
        } catch {
            localLoadFailed = true
        }
        if selectedPositionID == nil {
            selectedPositionID = session.pendingPositionIDs.first ?? session.declaration.positions.first?.id
        }
    }

    func saveProgress(_ updated: LeonardoGuidedSigningSession) async throws {
        try await library.signingStore.saveSession(updated, replacing: storedBaseline)
        storedBaseline = updated
    }

    private func restoreProgress(trustStore: LeonardoSigningTrustRegistry) async throws {
        guard let document else { throw LeonardoSigningError.integrityFailure }
        let restored = try await Self.restoreSigningProgress(
            exchange: initialExchange, document: document, resources: resources,
            localDocumentLocation: localDocumentLocation, store: library.signingStore,
            trustStore: trustStore
        )
        session = restored.session
        storedBaseline = restored.baseline
        let referencedIDs = Set(session.positions.values.compactMap { $0.assignment?.credentialID })
        trustedCredentials += trustStore.allCredentials.filter { credential in
            referencedIDs.contains(credential.id) && !trustedCredentials.contains { $0.id == credential.id }
        }
    }

    static func restoreSigningProgress(
        exchange: LeonardoSigningExchange, document: LeonardoDocument,
        resources: [LeonardoSigningResource], localDocumentLocation: String?,
        store: LeonardoSigningStore, trustStore: LeonardoSigningTrustRegistry
    ) async throws -> (session: LeonardoGuidedSigningSession, baseline: LeonardoGuidedSigningSession?) {
        let stored = try await store.session(id: exchange.session.id)
        let location = stored?.documentLocation ?? localDocumentLocation ?? "mobile://exchange/\(exchange.session.id)"
        if var local = stored {
            local.documentLocation = location
            let localCopy = try LeonardoSigningExchange(
                document: document, resources: resources, session: local,
                trustedCredentials: trustStore.allCredentials, at: Date()
            )
            let incoming = try exchange.reboundSession(onto: nil, documentLocation: location)
            if (try? localCopy.reboundSession(onto: incoming, documentLocation: location)) != nil {
                return (local, stored)
            }
        }

        let incoming = try exchange.reboundSession(onto: stored, documentLocation: location)
        let allKeysTrusted = exchange.trustedCredentials.allSatisfy {
            trustStore.credential(id: $0.id) == $0
        }
        guard allKeysTrusted else { return (incoming, stored) }
        try exchange.validate(against: document, resources: resources, trustStore: trustStore)
        guard !incoming.isPristine else { return (incoming, stored) }
        try await store.saveSession(incoming, replacing: stored)
        return (incoming, incoming)
    }

    func updateVerification(trustStore: LeonardoSigningTrustRegistry) {
        guard let document else { return }
        hasInvalidSeal = session.state == .invalidated
            || (session.snapshot.map { !$0.matches(document: document, resources: resources) } ?? false)
        verification = session.signatureVerification(document: document, resources: resources, trustStore: trustStore)
    }

    func enrollCredential(password: String) async {
        do {
            let enrolled = try await library.signingCredentialStore.enroll(password: password)
            credentialIDs = try await library.signingCredentialStore.credentialIDs()
            // Keychain ordering is not enrollment ordering. Keep the exact
            // credential returned by the enrollment operation selected even
            // when another credential sorts after it.
            selectedCredentialID = Self.selectedCredentialID(
                afterEnrollment: enrolled,
                availableIDs: credentialIDs
            ) ?? ""
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func acceptSelectedPublicKey() async {
        guard let credentialID = selectedTrustCredentialID,
              let credential = trustedCredentials.first(where: { $0.id == credentialID }) else { return }
        let normalizedInput = trustFingerprintInput
            .filter { $0.isHexDigit }
            .lowercased()
        guard normalizedInput == publicFingerprint(credential).filter({ $0.isHexDigit }).lowercased() else {
            errorMessage = spanish
                ? "La huella no coincide. Compruébala por la vía independiente indicada."
                : "The fingerprint does not match. Check it through the separate channel."
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await library.signingCredentialStore.trustPublicCredential(credential)
            let trustStore = try await library.signingCredentialStore.trustStore()
            // Once the last key is approved, reconcile and commit the copy
            // before the UI can continue or display a verified result.
            if untrustedPackageCredentials.count == 1 {
                try await restoreProgress(trustStore: trustStore)
            }
            locallyTrustedCredentialIDs.insert(credential.id)
            updateVerification(trustStore: trustStore)
            trustFingerprintInput = ""
            selectedTrustCredentialID = untrustedPackageCredentials.first?.id
            trustAccepted = untrustedPackageCredentials.isEmpty
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func exportSigningCopy(document: LeonardoDocument) {
        guard workflowAllowed else { return }
        do {
            let exchange = try LeonardoSigningExchange(
                document: document, resources: resources, session: session,
                trustedCredentials: trustedCredentials, at: Date()
            )
            exportDocument = try MobileSigningExchangeDocument(exporting: exchange)
            exporting = true
        } catch LeonardoSigningError.exchangeTooLarge {
            errorMessage = spanish
                ? "Esta copia de firma supera el tamaño máximo para el intercambio."
                : "This signing copy exceeds the exchange size limit."
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
