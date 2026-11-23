#if os(macOS)
import Foundation
import LeonardoSync

/// Applies an accepted peer receipt to the local working directory. It journals the exact
/// before/after transaction and the merged archive before any selected file is changed.
public actor DesktopPeerReceiptApplier: LeonardoSync.DesktopPeerReceiptApplier {
    private struct Integration {
        let copy: DesktopPeerCopy
        let appliedSnapshot: CorpusSnapshot
        let retainedBufferPaths: Set<String>
    }

    private let workingRoot: URL
    private let copies: any DesktopPeerCopyStore
    private let intents: any DesktopPeerReceiptIntentStore
    private let transactions: ScopedDesktopTransaction
    private let reader: ProjectCorpusReader
    private let limits: CorpusLimits
    private var changing = false

    public init(workingRoot: URL, copies: any DesktopPeerCopyStore,
                intents: any DesktopPeerReceiptIntentStore,
                transactionJournals: URL? = nil,
                limits: CorpusLimits = CorpusLimits()) {
        self.workingRoot = workingRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.copies = copies
        self.intents = intents
        let journals = transactionJournals ?? self.workingRoot.appendingPathComponent(".transactions", isDirectory: true)
        transactions = ScopedDesktopTransaction(journals: journals)
        reader = ProjectCorpusReader(limits: limits)
        self.limits = limits
    }

    public func apply(copyID: UUID, proposal: DesktopPeerProposal,
                      receipt: DesktopPeerProposalReceipt,
                      diskAtSend: CorpusSnapshot?) async throws -> DesktopPeerAcceptanceResult {
        try enter()
        defer { changing = false }
        guard let copy = try await copies.load(id: copyID) else { throw DesktopPeerWorkspaceError.unknownCopy }
        try validate(copy: copy, proposal: proposal, receipt: receipt, diskAtSend: diskAtSend)

        if let intent = try await intents.load(copyID: copyID) {
            try validate(intent: intent, copy: copy, proposal: proposal, receipt: receipt, diskAtSend: diskAtSend)
            if let persisted = try await transactions.recover(id: intent.transactionID, projectRoot: root(copyID)) {
                guard equivalent(persisted, intent.appliedSnapshot) else { throw SyncError.invalidSnapshot }
                let physical = try await currentDisk(copyID: copyID, selection: copy.selection)
                let integration = try copyForApplied(copy, proposal: proposal, receipt: receipt,
                                                     appliedSnapshot: physical)
                try await copies.save(integration.copy)
                try await intents.remove(copyID: copyID)
                return outcome(receipt: receipt, appliedSnapshot: integration.appliedSnapshot,
                               appliedNow: false, retained: integration.retainedBufferPaths)
            }
            // A prepared intent that rolled back, or an intent saved before journal creation,
            // can be rebuilt from the still-pending immutable proposal.
            try await intents.remove(copyID: copyID)
        }

        if copy.base == receipt.accepted {
            let physical = try await currentDisk(copyID: copyID, selection: copy.selection)
            try await intents.remove(copyID: copyID)
            return outcome(receipt: receipt, appliedSnapshot: physical, appliedNow: false,
                           retained: retainedBuffers(copy.current, appliedSnapshot: physical))
        }
        guard proposal.base == copy.base else { throw ReconciliationError.staleComparison }
        let root = try workingDirectory(copyID)
        let before = try await reader.snapshot(root: root, selection: copy.selection, revision: proposal.base.revision)
        let integration = try integrate(copy: copy, proposal: proposal, receipt: receipt,
                                        diskAtSend: diskAtSend, before: before)
        let transactionID = UUID()
        let intent = try DesktopPeerReceiptIntent(copyID: copyID, transactionID: transactionID,
            proposal: proposal, receipt: receipt, merged: integration.copy, before: before,
            appliedSnapshot: integration.appliedSnapshot, diskAtSend: diskAtSend,
            retainedBufferPaths: integration.retainedBufferPaths, limits: limits)
        try await intents.save(intent)
        do {
            _ = try await transactions.prepare(id: transactionID, projectRoot: root, selection: copy.selection,
                                               before: before, after: integration.appliedSnapshot)
        } catch {
            try? await intents.remove(copyID: copyID)
            throw error
        }
        _ = try await transactions.apply(id: transactionID, projectRoot: root)
        // A failure here intentionally retains the intent: recovery can finish the exact
        // transaction without replacing edits captured after the original proposal.
        try await copies.save(integration.copy)
        try await intents.remove(copyID: copyID)
        return outcome(receipt: receipt, appliedSnapshot: integration.appliedSnapshot,
                       appliedNow: true, retained: integration.retainedBufferPaths)
    }

    public func recover(copyID: UUID) async throws -> DesktopPeerAcceptanceResult? {
        try enter()
        defer { changing = false }
        guard let intent = try await intents.load(copyID: copyID) else { return nil }
        guard let copy = try await copies.load(id: copyID) else { throw DesktopPeerWorkspaceError.unknownCopy }
        try validate(intent: intent, copy: copy, proposal: intent.proposal, receipt: intent.receipt,
                     diskAtSend: intent.diskAtSend)
        guard let persisted = try await transactions.recover(id: intent.transactionID, projectRoot: root(copyID)) else {
            try await intents.remove(copyID: copyID)
            return nil
        }
        guard equivalent(persisted, intent.appliedSnapshot) else { throw SyncError.invalidSnapshot }
        let physical = try await currentDisk(copyID: copyID, selection: copy.selection)
        let integration = try copyForApplied(copy, proposal: intent.proposal, receipt: intent.receipt,
                                             appliedSnapshot: physical)
        try await copies.save(integration.copy)
        try await intents.remove(copyID: copyID)
        return outcome(receipt: intent.receipt, appliedSnapshot: integration.appliedSnapshot,
                       appliedNow: false, retained: integration.retainedBufferPaths)
    }

    private func integrate(copy: DesktopPeerCopy, proposal: DesktopPeerProposal,
                           receipt: DesktopPeerProposalReceipt, diskAtSend: CorpusSnapshot?,
                           before: CorpusSnapshot) throws -> Integration {
        let sent = Dictionary(uniqueKeysWithValues: proposal.proposed.files.map { ($0.path, $0) })
        let disk = Dictionary(uniqueKeysWithValues: before.files.map { ($0.path, $0) })
        let reference = diskAtSend.map { Dictionary(uniqueKeysWithValues: $0.files.map { ($0.path, $0) }) }
        var applied = Dictionary(uniqueKeysWithValues: receipt.accepted.files.map { ($0.path, $0) })
        var paths = Set(sent.keys).union(disk.keys)
        if let reference { paths.formUnion(reference.keys) }
        for path in paths {
            let changedAfterSend: Bool
            if let reference {
                changedAfterSend = disk[path]?.content != reference[path]?.content
            } else if sent[path]?.isUnsavedBuffer == true {
                // An old outbox did not retain the disk baseline. Draft paths are
                // deliberately ambiguous, so their current disk bytes are kept.
                changedAfterSend = true
            } else {
                changedAfterSend = disk[path]?.content != sent[path]?.content
            }
            guard changedAfterSend else { continue }
            if let file = disk[path] {
                applied[path] = CorpusFile(path: path, content: file.content)
            } else {
                applied.removeValue(forKey: path)
            }
        }
        let ordered = applied.values.sorted { $0.path < $1.path }
        let appliedSnapshot = CorpusSnapshot(revision: CorpusRevision.make(files: ordered), files: ordered)
        try proposal.selection.validate(appliedSnapshot, limits: limits)
        return try copyForApplied(copy, proposal: proposal, receipt: receipt, appliedSnapshot: appliedSnapshot)
    }

    private func copyForApplied(_ copy: DesktopPeerCopy, proposal: DesktopPeerProposal,
                                receipt: DesktopPeerProposalReceipt,
                                appliedSnapshot: CorpusSnapshot) throws -> Integration {
        var result = copy
        if result.base != receipt.accepted { try result.acknowledge(proposal, receipt: receipt) }
        let physical = Dictionary(uniqueKeysWithValues: appliedSnapshot.files.map { ($0.path, $0) })
        let retained = retainedBuffers(result.current, appliedSnapshot: appliedSnapshot)
        var merged = physical
        for path in retained {
            if let file = result.current.files.first(where: { $0.path == path }) { merged[path] = file }
        }
        let snapshot = CorpusSnapshot(revision: receipt.accepted.revision,
                                     files: merged.values.sorted { $0.path < $1.path })
        try result.capture(snapshot, limits: limits)
        return Integration(copy: result, appliedSnapshot: appliedSnapshot, retainedBufferPaths: retained)
    }

    private func retainedBuffers(_ current: CorpusSnapshot, appliedSnapshot: CorpusSnapshot) -> Set<String> {
        let physical = Dictionary(uniqueKeysWithValues: appliedSnapshot.files.map { ($0.path, $0) })
        return Set(current.files.compactMap { file in
            guard file.isUnsavedBuffer, file.content != physical[file.path]?.content else { return nil }
            return file.path
        })
    }

    private func currentDisk(copyID: UUID, selection: CorpusSelection) async throws -> CorpusSnapshot {
        try await reader.snapshot(root: workingDirectory(copyID), selection: selection)
    }

    private func validate(copy: DesktopPeerCopy, proposal: DesktopPeerProposal,
                          receipt: DesktopPeerProposalReceipt,
                          diskAtSend: CorpusSnapshot?) throws {
        try proposal.selection.validate(receipt.accepted, limits: limits)
        guard receipt.proposalID == proposal.id, receipt.projectID == proposal.projectID,
              copy.remoteProjectID == proposal.projectID, copy.selection == proposal.selection else {
            throw ReconciliationError.staleComparison
        }
        if let diskAtSend {
            try proposal.selection.validate(diskAtSend, limits: limits)
            guard diskAtSend.files.allSatisfy({ !$0.isUnsavedBuffer }) else { throw SyncError.invalidSnapshot }
        }
        guard proposal.base == copy.base || copy.base == receipt.accepted else {
            throw ReconciliationError.staleComparison
        }
    }

    private func validate(intent: DesktopPeerReceiptIntent, copy: DesktopPeerCopy,
                          proposal: DesktopPeerProposal, receipt: DesktopPeerProposalReceipt,
                          diskAtSend: CorpusSnapshot?) throws {
        guard intent.copyID == copy.id, intent.proposal == proposal, intent.receipt == receipt,
              intent.merged.id == copy.id, intent.merged.connectionID == copy.connectionID,
              intent.merged.remoteProjectID == copy.remoteProjectID,
              intent.merged.selection == copy.selection else { throw SyncError.invalidSnapshot }
        if let diskAtSend, intent.diskAtSend != diskAtSend { throw SyncError.invalidSnapshot }
    }

    private func outcome(receipt: DesktopPeerProposalReceipt, appliedSnapshot: CorpusSnapshot,
                         appliedNow: Bool,
                         retained: Set<String>) -> DesktopPeerAcceptanceResult {
        DesktopPeerAcceptanceResult(receipt: receipt, appliedNow: appliedNow,
                                     appliedSnapshot: appliedSnapshot,
                                     retainedBufferPaths: retained)
    }

    private func equivalent(_ lhs: CorpusSnapshot, _ rhs: CorpusSnapshot) -> Bool {
        lhs.files.sorted { $0.path < $1.path } == rhs.files.sorted { $0.path < $1.path }
    }

    private func root(_ id: UUID) throws -> URL { try workingDirectory(id) }

    private func workingDirectory(_ id: UUID) throws -> URL {
        let url = workingRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else { throw SyncError.invalidPath }
        return url
    }

    private func enter() throws {
        guard !changing else { throw DesktopTransactionError.busy }
        changing = true
    }
}
#endif
