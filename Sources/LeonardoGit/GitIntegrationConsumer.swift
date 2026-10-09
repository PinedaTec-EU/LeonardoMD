import Foundation
import LeonardoSync

/// The result of consuming one exact desktop integration or a later source
/// branch revision. Reconciliation outcomes preserve the current baseline so
/// callers can show a stable status without repeatedly throwing the same
/// stale-branch condition.
public enum GitIntegrationConsumptionOutcome: Sendable {
    case noResult
    case awaitingIntegration
    case consumed(project: OfflineProject, baseline: GitBaseline)
    case alreadyIntegrated
    case requiresReconciliation
}

/// Shared Git integration consumer used by the mobile adapter. It validates
/// the immutable integration result before selected blobs, then accepts a
/// normal branch advance only when bounded metadata proves both safe ancestry
/// and preservation of every selected path changed by the desktop result.
public struct GitIntegrationConsumer: Sendable {
    private let reader: GitRemoteReader
    private let deviceID: UUID

    public init(reader: GitRemoteReader, deviceID: UUID) {
        self.reader = reader
        self.deviceID = deviceID
    }

    public func consume(_ project: OfflineProject,
                        connection: GitProjectConnection,
                        currentBaseline: GitBaseline? = nil,
                        maximumAncestryCommits: Int = 256) async throws -> GitIntegrationConsumptionOutcome {
        guard project.mode == .git,
              project.id == connection.projectID,
              project.scope == connection.scope else {
            throw SyncError.invalidSnapshot
        }

        let discovery = try await reader.discover()
        let refs = try reader.integrationRefs(from: discovery,
                                              projectID: project.id,
                                              deviceID: deviceID)

        if project.publication == .sent {
            return try await consumeSentProposal(project, refs: refs, discovery: discovery)
        }

        // Once a desktop result is the current baseline, the immutable result
        // ref must not be used as a reason to refresh an old source tip. Read
        // its metadata only, then decide whether the configured normal branch
        // has made a safe, explicit advance from the recorded tree basis.
        // A consumed integration may have its remote immutable ref pruned, so
        // the persisted baseline is also an authenticated provenance source.
        switch try await resolveCurrentIntegration(project: project, connection: connection,
                                                   refs: refs, discovery: discovery,
                                                   currentBaseline: currentBaseline) {
        case .ordinaryBaseline:
            return .noResult
        case .requiresReconciliation:
            return .requiresReconciliation
        case .integration(let currentIntegration):
            return try await consumeSourceAdvance(project, connection: connection,
                                                  currentIntegration: currentIntegration,
                                                  discovery: discovery,
                                                  maximumAncestryCommits: maximumAncestryCommits)
        }
    }

    private func consumeSentProposal(_ project: OfflineProject,
                                     refs: [GitIntegrationRef],
                                     discovery: GitRemoteDiscovery) async throws -> GitIntegrationConsumptionOutcome {
        guard let proposalID = project.publishedRevision else {
            throw SyncError.invalidSnapshot
        }
        guard let candidate = refs.first(where: { $0.proposalCommitID == proposalID }) else {
            return .awaitingIntegration
        }

        let loaded = try await load(candidate, discovery: discovery)
        try Task.checkCancellation()
        guard loaded.result.projectID == project.id,
              loaded.result.deviceID == deviceID,
              loaded.result.proposalCommitID == proposalID,
              loaded.result.baseRevision == project.base.revision,
              loaded.result.scope == project.scope else {
            throw SyncError.invalidSnapshot
        }

        var updated = project
        try updated.acceptIntegration(loaded.snapshot)
        return .consumed(project: updated, baseline: loaded.metadata.baseline)
    }

    private enum CurrentIntegrationLookup: Sendable {
        case ordinaryBaseline
        case integration(IntegrationMetadata)
        case requiresReconciliation
    }

    private func resolveCurrentIntegration(project: OfflineProject,
                                           connection: GitProjectConnection,
                                           refs: [GitIntegrationRef],
                                           discovery: GitRemoteDiscovery,
                                           currentBaseline: GitBaseline?) async throws -> CurrentIntegrationLookup {
        if let candidate = refs.first(where: { reference in
            guard let advertised = discovery.references.first(where: { $0.name == reference.name }) else {
                return false
            }
            return advertised.objectID == project.base.revision
        }) {
            let metadata = try await loadMetadata(candidate, discovery: discovery)
            return .integration(metadata)
        }
        if let baseline = currentBaseline, baseline.commitID == project.base.revision {
            do {
                guard let persisted = try Self.integrationMetadata(in: baseline) else {
                    // This is an ordinary baseline, so the normal refresher
                    // still owns its branch advancement.
                    return .ordinaryBaseline
                }
                return .integration(persisted)
            } catch {
                // The project claims to be based on an integration commit,
                // but its local provenance is malformed. Never fall through
                // to the ordinary branch refresher in that state.
                return .requiresReconciliation
            }
        }
        guard connection.lastPublishedCommit == nil else {
            // A prior device publication means this project may have consumed
            // an integration whose immutable ref was later pruned. Without
            // the persisted baseline provenance, a normal refresher could
            // overwrite that accepted tree with the old source branch.
            return .requiresReconciliation
        }
        return .ordinaryBaseline
    }

    private func consumeSourceAdvance(_ project: OfflineProject,
                                      connection: GitProjectConnection,
                                      currentIntegration: IntegrationMetadata,
                                      discovery: GitRemoteDiscovery,
                                      maximumAncestryCommits: Int) async throws -> GitIntegrationConsumptionOutcome {
        let result = currentIntegration.result
        guard result.projectID == project.id,
              result.deviceID == deviceID,
              result.integrationCommitID == project.base.revision,
              result.scope == project.scope else {
            return .requiresReconciliation
        }
        do {
            try result.validate(accepted: project.base)
        } catch {
            return .requiresReconciliation
        }
        guard let sourceTip = discovery.references.first(where: { $0.name == connection.branch })?.objectID else {
            return .requiresReconciliation
        }
        if sourceTip == result.sourceRevision || sourceTip == result.proposalCommitID ||
            sourceTip == result.integrationCommitID {
            return .alreadyIntegrated
        }
        guard !project.hasLocalChanges else { return .requiresReconciliation }

        // An explicit integration ancestor allows ordinary history to decide
        // selected paths, including an intentional revert.
        let integrationProof = try await reader.proveAncestry(
            ancestor: result.integrationCommitID, descendant: sourceTip,
            discovery: discovery, maximumCommits: maximumAncestryCommits)
        if integrationProof == .proven {
            return try await consumeSourceTip(project, sourceTip: sourceTip,
                                              discovery: discovery)
        }
        guard let metadata = try await safeSourceAdvanceMetadata(
            sourceRevision: result.sourceRevision, sourceTip: sourceTip,
            integration: currentIntegration.baseline, scope: result.scope,
            discovery: discovery, maximumAncestryCommits: maximumAncestryCommits) else {
            return .requiresReconciliation
        }
        return try await consumeSourceTip(project, sourceTip: sourceTip,
                                          discovery: discovery, metadata: metadata)
    }

    private func safeSourceAdvanceMetadata(sourceRevision: String,
                                           sourceTip: String,
                                           integration: GitBaseline,
                                           scope: CorpusScope,
                                           discovery: GitRemoteDiscovery,
                                           maximumAncestryCommits: Int) async throws -> GitRepositoryMetadata? {
        let sourceProof = try await reader.proveAncestryMetadata(
            ancestor: sourceRevision, descendant: sourceTip,
            discovery: discovery, maximumCommits: maximumAncestryCommits)
        guard sourceProof.proof == .proven,
              let sourceBaseline = try? sourceProof.baseline(commitID: sourceRevision) else {
            return nil
        }

        // Ancestry alone is insufficient: require every accepted add/change/
        // delete from sourceRevision to be present in the candidate tree.
        let metadata = try await reader.metadata(commitID: sourceTip, discovery: discovery)
        guard Self.candidatePreservesAcceptedChanges(source: sourceBaseline,
                                                      integration: integration,
                                                      candidate: metadata.baseline,
                                                      scope: scope) else {
            return nil
        }
        return metadata
    }

    private func consumeSourceTip(_ project: OfflineProject, sourceTip: String,
                                  discovery: GitRemoteDiscovery,
                                  metadata: GitRepositoryMetadata? = nil) async throws -> GitIntegrationConsumptionOutcome {
        // Metadata is fetched only after the ancestry and selected-path safety
        // decisions. The selected blobs are requested from this exact tip.
        let resolvedMetadata: GitRepositoryMetadata
        if let metadata {
            resolvedMetadata = metadata
        } else {
            resolvedMetadata = try await reader.metadata(commitID: sourceTip, discovery: discovery)
        }
        let snapshot = try await reader.snapshot(metadata: resolvedMetadata, scope: project.scope)
        try Task.checkCancellation()
        var updated = project
        try updated.replaceGitSnapshot(snapshot)
        return .consumed(project: updated, baseline: resolvedMetadata.baseline)
    }

    private struct IntegrationMetadata: Sendable {
        let result: GitIntegrationResult
        let baseline: GitBaseline
    }

    private struct LoadedIntegration: Sendable {
        let result: GitIntegrationResult
        let metadata: GitRepositoryMetadata
        let snapshot: CorpusSnapshot
    }

    private func load(_ ref: GitIntegrationRef,
                      discovery: GitRemoteDiscovery) async throws -> LoadedIntegration {
        guard let advertised = discovery.references.first(where: { $0.name == ref.name }),
              let integrationCommitID = advertised.objectID else {
            throw GitWireError.invalidObjectID
        }
        let metadata = try await reader.metadata(commitID: integrationCommitID, discovery: discovery)
        guard let commit = metadata.objects.first(where: {
            $0.id == integrationCommitID && $0.kind == .commit
        }) else { throw GitWireError.invalidPack }
        let result = try GitIntegrationResult.parse(commit: commit,
                                                    expectedCommitID: integrationCommitID)
        guard result.integrationRef == ref,
              result.projectID == ref.projectID,
              result.deviceID == ref.deviceID else {
            throw GitWireError.invalidPack
        }
        let snapshot = try await reader.snapshot(metadata: metadata, scope: result.scope)
        try result.validate(accepted: snapshot)
        return LoadedIntegration(result: result, metadata: metadata, snapshot: snapshot)
    }

    private func loadMetadata(_ ref: GitIntegrationRef,
                              discovery: GitRemoteDiscovery) async throws -> IntegrationMetadata {
        guard let advertised = discovery.references.first(where: { $0.name == ref.name }),
              let integrationCommitID = advertised.objectID else {
            throw GitWireError.invalidObjectID
        }
        let metadata = try await reader.metadata(commitID: integrationCommitID, discovery: discovery)
        guard let commit = metadata.objects.first(where: {
            $0.id == integrationCommitID && $0.kind == .commit
        }) else { throw GitWireError.invalidPack }
        let result = try GitIntegrationResult.parse(commit: commit,
                                                    expectedCommitID: integrationCommitID)
        guard result.integrationRef == ref else { throw GitWireError.invalidPack }
        return IntegrationMetadata(result: result, baseline: metadata.baseline)
    }

    private static func integrationMetadata(in baseline: GitBaseline) throws -> IntegrationMetadata? {
        guard let commit = baseline.objects.first(where: {
            $0.id == baseline.commitID && $0.kind == .commit
        }) else { throw GitWireError.invalidPack }
        guard let text = String(data: commit.data, encoding: .utf8),
              let headerText = text.components(separatedBy: "\n\n").first,
              headerText.split(separator: "\n").contains(where: {
                  $0.hasPrefix("little-leonardo-integration-project ")
              }) else {
            return nil
        }
        let result = try GitIntegrationResult.parse(commit: commit, expectedCommitID: baseline.commitID)
        return IntegrationMetadata(result: result, baseline: baseline)
    }

    private struct SelectedEntry: Equatable {
        let objectID: String
        let executable: Bool
    }

    private static func candidatePreservesAcceptedChanges(source: GitBaseline,
                                                          integration: GitBaseline,
                                                          candidate: GitBaseline,
                                                          scope: CorpusScope) -> Bool {
        guard let sourceFiles = try? selectedEntries(source, scope: scope),
              let integrationFiles = try? selectedEntries(integration, scope: scope),
              let candidateFiles = try? selectedEntries(candidate, scope: scope) else {
            return false
        }
        let paths = Set(sourceFiles.keys).union(integrationFiles.keys)
        let acceptedChanges = paths.filter { sourceFiles[$0] != integrationFiles[$0] }
        return acceptedChanges.allSatisfy { candidateFiles[$0] == integrationFiles[$0] }
    }

    private static func selectedEntries(_ baseline: GitBaseline,
                                       scope: CorpusScope) throws -> [String: SelectedEntry] {
        let files: [GitFolderIndex.File]
        do {
            files = try baseline.index.files(in: scope)
        } catch SyncError.outsideScope {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: files.map {
            ($0.path, SelectedEntry(objectID: $0.objectID, executable: $0.executable))
        })
    }
}
