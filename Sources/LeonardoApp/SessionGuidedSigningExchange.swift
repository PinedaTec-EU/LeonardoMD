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
    func exportGuidedSigningExchange() async {
        guard let current = guidedSigningSession,
              let expectedLocation = guidedSigningLocation,
              await flushPreviewEdits(),
              guidedSigningSession == current, guidedSigningLocation == expectedLocation,
              let document = leonardoDocument else { return }
        let expectedContent = content
        let expectedSnapshot = snapshot
        guard await guidedSigningExchangeSourceIsSaved(
            location: expectedLocation, content: expectedContent, session: current, snapshot: expectedSnapshot
        ) else { return }
        do {
            let exchange = try LeonardoSigningExchange(
                document: document,
                resources: try guidedSigningResources(),
                session: current,
                trustedCredentials: guidedSigningTrustStore?.allCredentials.filter { credential in
                    current.positions.values.contains { progress in
                        progress.assignment?.credentialID == credential.id
                    }
                } ?? [],
                at: Date()
            )
            let data = try LeonardoSigningExchange.encoded(exchange)
            let panel = NSSavePanel()
            panel.title = L10n.text("Export signing copy")
            panel.nameFieldStringValue = documentURL?.deletingPathExtension().lastPathComponent
                .appending("-signing-copy.json") ?? "Leonardo-signing-copy.json"
            panel.allowedContentTypes = [.json]
            presentFilePanel(panel) { [weak self] destination in
                Task {
                    await self?.writeGuidedSigningExchange(
                        data,
                        to: destination,
                        expectedLocation: expectedLocation,
                        expectedContent: expectedContent,
                        expectedSession: current,
                        expectedSnapshot: expectedSnapshot
                    )
                }
            }
        } catch LeonardoSigningError.exchangeTooLarge {
            guidedSigningActionProblem = L10n.text("This signing copy exceeds the exchange size limit.")
        } catch LeonardoSigningError.remoteImagesNotSealable {
            guidedSigningActionProblem = L10n.text("Replace online images with local files before signing.")
        } catch {
            guidedSigningError = String(describing: error)
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
        expectedLocation: String,
        expectedContent: String,
        expectedSession: LeonardoGuidedSigningSession,
        expectedSnapshot: DocumentSnapshot?
    ) async {
        guard await guidedSigningExchangeSourceIsSaved(
                  location: expectedLocation, content: expectedContent,
                  session: expectedSession, snapshot: expectedSnapshot
              ) else { return }
        do {
            try InstancePathOwnership.shared.claim(destination)
            try Self.writeSigningExchangeAtomically(data, to: destination)
            saveStatus = L10n.text("Signing copy exported")
        } catch {
            guidedSigningError = String(describing: error)
        }
    }

    func readGuidedSigningExchange(from source: URL) async {
        let initialLocation = guidedSigningLocation
        let initialSession = guidedSigningSession
        guard await flushPreviewEdits(),
              guidedSigningLocation == initialLocation, guidedSigningSession == initialSession else { return }
        let expectedLocation = guidedSigningLocation
        let expectedContent = content
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
            let exchange = try LeonardoSigningExchange.decoded(data)
            try await importGuidedSigningExchange(
                exchange,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent
            )
        } catch {
            guidedSigningError = String(describing: error)
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
        let trust = try await signingExchangeTrust(exchange, isCurrent: isCurrent)
        try exchange.validate(against: document, resources: localResources, trustStore: trust.effective)
        let localSessions = try await guidedSigningStore.sessions()
            .filter { $0.documentLocation == expectedLocation }
        guard isCurrent() else { throw LeonardoSigningError.integrityFailure }
        let (local, pristineReplacement) = try signingExchangeBaseline(exchange, localSessions: localSessions)
        guard expectedSession == (local ?? pristineReplacement) else {
            throw LeonardoSigningError.integrityFailure
        }
        let rebound = try exchange.reboundSession(onto: local, documentLocation: expectedLocation)
        guard await savedSourceMatches() else { return }
        for credential in trust.unknown {
            guard isCurrent() else { throw LeonardoSigningError.integrityFailure }
            try await guidedSigningCredentialStore.trustPublicCredential(credential)
        }
        guard await savedSourceMatches() else { return }
        guard localResources == (try guidedSigningResources()) else { throw LeonardoSigningError.integrityFailure }
        if let pristineReplacement {
            try await guidedSigningStore.replacePristineSession(
                id: pristineReplacement.id, baseline: pristineReplacement, with: rebound
            )
        } else {
            try await guidedSigningStore.saveSession(rebound, replacing: local)
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
        guidedSigningStatus = L10n.text("Signed copy imported after local integrity and trust checks.")
    }

    private func signingExchangeTrust(
        _ exchange: LeonardoSigningExchange,
        isCurrent: () -> Bool
    ) async throws -> (effective: LeonardoSigningTrustRegistry, unknown: [LeonardoSigningCredential]) {
        let local = try await guidedSigningCredentialStore.trustStore()
        guard isCurrent() else { throw LeonardoSigningError.integrityFailure }
        let unknown = exchange.trustedCredentials.filter { local.credential(id: $0.id) != $0 }
        guard !unknown.isEmpty else { return (local, []) }
        guard confirmImportedPublicKeys(unknown) else { throw LeonardoSigningError.trustStoreRequired }
        guard isCurrent() else { throw LeonardoSigningError.integrityFailure }
        return (try LeonardoSigningTrustRegistry(credentials: local.allCredentials + unknown), unknown)
    }

    @MainActor
    private func signingExchangeBaseline(
        _ exchange: LeonardoSigningExchange,
        localSessions: [LeonardoGuidedSigningSession]
    ) throws -> (local: LeonardoGuidedSigningSession?, pristineReplacement: LeonardoGuidedSigningSession?) {
        // A deliberate correction preserves the old sidecar session at this
        // path. Only sessions for this exact document identity and semantic
        // revision can participate in the import CAS; older revisions remain
        // audit history and must not block a valid current copy.
        let currentRevisionSessions = localSessions.filter {
            $0.documentID == exchange.documentID
                && $0.initialRevision == exchange.documentRevision
        }
        guard currentRevisionSessions.count <= 1 else {
            // Multiple sessions for one exact revision are a fork, even if
            // one happens to be pristine. Never choose between them.
            throw LeonardoSigningError.staleStorage
        }
        let local = currentRevisionSessions.first { $0.id == exchange.session.id }
        let pristineReplacement = local == nil && currentRevisionSessions.count == 1
            ? currentRevisionSessions.first(where: { $0.isPristine })
            : nil
        guard local != nil || currentRevisionSessions.isEmpty || pristineReplacement != nil else {
            // A different local session means this file already has progress
            // from another signing copy for this revision. Never overwrite or
            // merge that fork, while historical revisions remain untouched.
            throw LeonardoSigningError.staleStorage
        }
        guard localSessions.isEmpty || !currentRevisionSessions.isEmpty else {
            // There is local signing history, but no sidecar for this exact
            // source revision. Do not make import the back door around the
            // same exact path/ID/revision binding used by preparation.
            throw LeonardoSigningError.staleStorage
        }
        return (local, pristineReplacement)
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
