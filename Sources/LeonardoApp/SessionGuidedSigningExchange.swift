import AppKit
import CryptoKit
import Darwin
import Foundation
import LeonardoCore
import LeonardoSync
import UniformTypeIdentifiers

extension AppSession {
    /// Exports an explicit offline signing exchange. The source document is
    /// never changed and the package contains only public trust records and
    /// the current sidecar progress; local paths and private keys stay local.
    func exportGuidedSigningExchange(chooseDestination: ((NSSavePanel) async -> URL?)? = nil) async {
        guard let current = guidedSigningSession,
              let expectedLocation = guidedSigningLocation,
              let documentURL, let identity = leonardoExportIdentity(for: documentURL),
              !stopped, !busy, !saving, !isClosing, !isSyncSuspended, fileOperationCount == 0,
              await flushPreviewEdits(),
              guidedSigningSession == current, guidedSigningLocation == expectedLocation,
              leonardoExportIdentityIsCurrent(identity),
              let document = leonardoDocument else { return }
        let expectedContent = content
        let expectedSnapshot = snapshot
        guard await guidedSigningExchangeSourceIsSaved(
            location: expectedLocation, content: expectedContent, session: current, snapshot: expectedSnapshot
        ) else { return }
        do {
            let resources = try guidedSigningResources()
            let exchange = try LeonardoSigningExchange(
                document: document,
                resources: resources,
                session: current,
                trustedCredentials: guidedSigningTrustStore?.allCredentials.filter { credential in
                    current.positions.values.contains { progress in
                        progress.assignment?.credentialID == credential.id
                    }
                } ?? [],
                at: Date()
            )
            let panel = NSSavePanel()
            let name = (identity.sourceURL ?? identity.documentURL).deletingPathExtension().lastPathComponent
            let data: Data
            if current.declaration.method == .certificate {
                let suffix = identity.documentURL.pathExtension.lowercased() == "mdlr" ? ".mdlr" : ".mdlf"
                data = try LeonardoEmbeddedSigning.archive(exchange, documentName: name + suffix)
                panel.title = L10n.text("Save signed Leonardo document…")
                panel.message = L10n.text("The package includes public certificates and declared signer details.")
                panel.nameFieldStringValue = name + "-signed.mdlz"
                panel.allowedContentTypes = [UTType(filenameExtension: "mdlz") ?? .archive]
            } else {
                data = try LeonardoSigningExchange.encoded(exchange)
                panel.title = L10n.text("Export signing copy")
                panel.nameFieldStringValue = name + "-signing-copy.json"
                panel.allowedContentTypes = [.json]
            }
            let destination: URL?
            if let chooseDestination {
                destination = await chooseDestination(panel)
            } else {
                destination = await NativeDialog.destination(panel, on: presentationWindow)
            }
            guard let destination else { return }
            await writeGuidedSigningExchange(
                data,
                to: destination,
                identity: identity,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: current,
                expectedSnapshot: expectedSnapshot,
                expectedResources: resources
            )
        } catch LeonardoSigningError.exchangeTooLarge {
            guidedSigningActionProblem = L10n.text("This signing copy exceeds the exchange size limit.")
        } catch {
            reportGuidedSigningActionFailure(error, blocksReview: current.snapshot != nil)
        }
    }

    /// Opens a signed-copy exchange and merges it only when the local source,
    /// snapshot, assignments and signature-chain prefix still match. Unknown
    /// public keys are shown with fingerprints and must be checked through a
    /// separate channel before they are stored in the public-only trust area.
    func importGuidedSigningExchange() {
        guard documentURL != nil else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Import signed copy")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        presentFilePanel(panel) { [weak self] source in
            Task { await self?.readGuidedSigningExchange(from: source) }
        }
    }

    private func writeGuidedSigningExchange(
        _ data: Data,
        to destination: URL,
        identity: LeonardoExportIdentity,
        expectedLocation: String,
        expectedContent: String,
        expectedSession: LeonardoGuidedSigningSession,
        expectedSnapshot: DocumentSnapshot?,
        expectedResources: [LeonardoSigningResource]
    ) async {
        guard !stopped, !busy, !saving, !isClosing, !isSyncSuspended,
              !isCapturingPreview, fileOperationCount == 0,
              leonardoExportIdentityIsCurrent(identity) else { return }
        let sources = leonardoExportSources(for: identity)
        let canonicalDestination = ProcessFileLock.canonicalURL(destination)
        guard !sources.contains(where: { ProcessFileLock.canonicalURL($0) == canonicalDestination }) else {
            guidedSigningActionProblem = L10n.text("Choose another file to keep both versions.")
            return
        }
        fileOperationCount += 1
        busy = true
        defer {
            busy = false
            fileOperationCount -= 1
        }
        do {
            try await authorizeLeonardoExport(sources: sources, destinationURL: destination)
            guard await guidedSigningExchangeSourceIsSaved(
                location: expectedLocation, content: expectedContent,
                session: expectedSession, snapshot: expectedSnapshot
            ), leonardoExportMayWrite(identity: identity, content: expectedContent,
                                      snapshotFingerprint: expectedSnapshot?.fingerprint) else { return }
            guard (try? guidedSigningResources()) == expectedResources else {
                if expectedSession.snapshot == nil {
                    guidedSigningActionProblem = L10n.text("A referenced image changed. Review the document and export a new signing copy.")
                } else {
                    markGuidedSigningSnapshotChanged()
                }
                return
            }
            for path in sources + [destination] {
                try NativeReconciliationLease.shared.check(path, intent: .document)
            }
            try InstancePathOwnership.shared.claim(destination)
            try Self.writeSigningExchangeAtomically(data, to: destination)
            saveStatus = L10n.text("Signing copy exported")
        } catch {
            reportGuidedSigningActionFailure(error, blocksReview: false)
        }
    }

    func readGuidedSigningExchange(from source: URL) async {
        let initialLocation = guidedSigningLocation
        let initialSession = guidedSigningSession
        guard await flushPreviewEdits(),
              guidedSigningLocation == initialLocation, guidedSigningSession == initialSession else { return }
        let expectedLocation = guidedSigningLocation
        let expectedContent = content
        let exchange: LeonardoSigningExchange
        do {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize <= LeonardoSigningExchange.maximumEnvelopeBytes else {
                throw LeonardoSigningError.storageFailure
            }
            let data = try Data(contentsOf: source, options: [.mappedIfSafe])
            guard data.count <= LeonardoSigningExchange.maximumEnvelopeBytes else {
                throw LeonardoSigningError.storageFailure
            }
            exchange = try LeonardoSigningExchange.decoded(data)
        } catch {
            guidedSigningActionProblem = L10n.text("Choose a readable, valid signing copy and try again.")
            return
        }
        do {
            try await importGuidedSigningExchange(
                exchange,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent
            )
        } catch {
            guard guidedSigningLocation == expectedLocation, content == expectedContent else { return }
            reportGuidedSigningActionFailure(error)
        }
    }

    private func importGuidedSigningExchange(
        _ exchange: LeonardoSigningExchange,
        expectedLocation: String?,
        expectedContent: String
    ) async throws {
        guard let expectedLocation,
              let expectedSession = guidedSigningSession,
              guidedSigningViewStateMatches(
                  expectedLocation: expectedLocation,
                  expectedContent: expectedContent,
                  expectedSession: expectedSession
              ),
              let document = leonardoDocument else {
            throw LeonardoSigningError.integrityFailure
        }
        let expectedSnapshot = snapshot
        func isCurrent() -> Bool {
            guidedSigningViewStateMatches(
                expectedLocation: expectedLocation, expectedContent: expectedContent, expectedSession: expectedSession
            )
        }
        func savedSourceMatches() async -> Bool {
            await guidedSigningExchangeSourceIsSaved(
                location: expectedLocation, content: expectedContent, session: expectedSession, snapshot: expectedSnapshot
            )
        }

        guard await savedSourceMatches() else { return }
        let localResources = try guidedSigningResources()
        // Check the persisted local revision on its own before comparing the
        // incoming history. A rejected copy does not invalidate a sound draft.
        let currentRevisionSessions = try await guidedSigningStore.sessions().filter {
            $0.documentLocation == expectedLocation
                && $0.documentID == expectedSession.documentID
                && $0.initialRevision == expectedSession.initialRevision
        }
        guard isCurrent(), currentRevisionSessions == [expectedSession] else {
            throw LeonardoSigningError.staleStorage
        }
        let matchesSession = expectedSession.id == exchange.session.id
        guard matchesSession || expectedSession.isPristine else {
            reportOutdatedSigningCopy()
            return
        }
        let rebound: LeonardoGuidedSigningSession
        do {
            rebound = try exchange.reboundSession(onto: matchesSession ? expectedSession : nil,
                                                  documentLocation: expectedLocation)
        } catch LeonardoSigningError.staleStorage {
            reportOutdatedSigningCopy()
            return
        } catch {
            reportGuidedSigningActionFailure(error, blocksReview: false)
            return
        }

        guard let trust = try await signingExchangeTrust(exchange, isCurrent: isCurrent) else { return }
        do {
            try exchange.validate(against: document, resources: localResources, trustStore: trust.effective)
        } catch {
            reportGuidedSigningActionFailure(error, blocksReview: false)
            return
        }
        guard await savedSourceMatches() else { return }
        for credential in trust.unknown {
            guard isCurrent() else { throw LeonardoSigningError.integrityFailure }
            try await guidedSigningCredentialStore.trustPublicCredential(credential)
        }
        guard await savedSourceMatches() else { return }
        guard localResources == (try guidedSigningResources()) else { throw LeonardoSigningError.integrityFailure }
        if matchesSession {
            try await guidedSigningStore.saveSession(rebound, replacing: expectedSession)
        } else {
            try await guidedSigningStore.replacePristineSession(
                id: expectedSession.id, baseline: expectedSession, with: rebound
            )
        }
        guard isCurrent() else { throw LeonardoSigningError.integrityFailure }
        guidedSigningSession = rebound
        let committedTrust = try await guidedSigningCredentialStore.trustStore()
        guard guidedSigningLocation == expectedLocation, content == expectedContent,
              guidedSigningSession == rebound else {
            throw LeonardoSigningError.integrityFailure
        }
        guidedSigningTrustStore = committedTrust
        guidedSigningVerification = rebound.signatureVerification(
            document: document,
            resources: localResources,
            trustStore: committedTrust
        )
        refreshGuidedSigningTargets()
        guidedSigningError = nil
        guidedSigningActionProblem = nil
        guidedSigningStatus = exchange.requiresLocalReview(comparedTo: rebound)
            ? L10n.text("Signing copy imported. Review and confirm the remaining locations on this Mac before signing.")
            : L10n.text("Signed copy imported after local integrity and trust checks.")
    }

    private func signingExchangeTrust(
        _ exchange: LeonardoSigningExchange,
        isCurrent: () -> Bool
    ) async throws -> (effective: LeonardoSigningTrustRegistry, unknown: [LeonardoSigningCredential])? {
        let local = try await guidedSigningCredentialStore.trustStore()
        guard isCurrent() else { throw LeonardoSigningError.integrityFailure }
        let unknown = exchange.trustedCredentials.filter { local.credential(id: $0.id) != $0 }
        guard !unknown.isEmpty else { return (local, []) }
        let effective: LeonardoSigningTrustRegistry
        do {
            effective = try LeonardoSigningTrustRegistry(credentials: local.allCredentials + unknown)
        } catch {
            reportGuidedSigningActionFailure(error, blocksReview: false)
            return nil
        }
        let personal = unknown.filter { $0.certificateChain == nil }
        guard personal.isEmpty || confirmImportedPublicKeys(personal) else { return nil }
        guard isCurrent() else { throw LeonardoSigningError.integrityFailure }
        return (effective, unknown)
    }

    private func reportOutdatedSigningCopy() {
        guidedSigningActionProblem = L10n.text("This signing copy does not match the progress saved on this Mac. Use a current copy.")
    }

    private func confirmImportedPublicKeys(_ credentials: [LeonardoSigningCredential]) -> Bool {
        let fields = credentials.map { credential -> (LeonardoSigningCredential, NSTextField) in
            let field = NSTextField(string: "")
            field.placeholderString = L10n.text("Enter fingerprint received separately")
            field.translatesAutoresizingMaskIntoConstraints = false
            return (credential, field)
        }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        for (credential, field) in fields {
            let label = NSTextField(labelWithString: "\(credential.id)\n\(Self.publicFingerprint(credential))")
            label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(field)
        }
        stack.frame = NSRect(x: 0, y: 0, width: 430, height: CGFloat(fields.count * 78))
        let alert = NSAlert()
        alert.messageText = L10n.text("Verify public signing keys")
        alert.informativeText = L10n.text("Compare every fingerprint through a separate trusted channel. The exchange file is not itself a trust anchor.")
        alert.accessoryView = stack
        alert.addButton(withTitle: L10n.text("Trust and import"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return fields.allSatisfy { credential, field in
            Self.normalizedFingerprint(field.stringValue) == Self.normalizedFingerprint(Self.publicFingerprint(credential))
        }
    }

    private static func publicFingerprint(_ credential: LeonardoSigningCredential) -> String {
        SHA256.hash(data: credential.publicKey).map { String(format: "%02x", $0) }
            .joined(separator: ":")
    }

    private static func normalizedFingerprint(_ value: String) -> String {
        value.filter(\.isHexDigit).lowercased()
    }

    private static func writeSigningExchangeAtomically(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
        ) else { throw LeonardoSigningError.storageFailure }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            guard Darwin.rename(temporary.path, destination.path) == 0 else {
                throw LeonardoSigningError.storageFailure
            }
        } catch let error as LeonardoSigningError {
            throw error
        } catch {
            throw LeonardoSigningError.storageFailure
        }
    }
}
