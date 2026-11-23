import Foundation
import LeonardoCore

extension AppSession {
    func discardPackageWorkspace() {
        guard let packageWorkspace else { return }
        saveTask?.cancel()
        self.packageWorkspace = nil
        queuePackageWorkspaceDisposal(packageWorkspace)
    }

    /// Queues temporary workspace deletion without performing filesystem I/O
    /// on the main actor. The queue joins the tracked save task first, so a
    /// detached repack cannot read or commit through a deleted extraction.
    func disposePackageWorkspace(_ workspace: LeonardoPackageWorkspace) async {
        queuePackageWorkspaceDisposal(workspace)
        // A stopped operation must unwind its busy/file-operation scope before
        // retirement can join it. finishRevocation owns the final queue join.
        if !stopped { await waitForPackageWorkspaceDisposal() }
    }

    func queuePackageWorkspaceDisposal(_ workspace: LeonardoPackageWorkspace) {
        pendingPackageWorkspaceDisposals.append((workspace, stopped))
        startPackageWorkspaceDisposal()
    }

    func waitForPackageWorkspaceDisposal() async {
        while let task = packageWorkspaceDisposalTask {
            await task.value
        }
    }

    private func startPackageWorkspaceDisposal() {
        guard packageWorkspaceDisposalTask == nil else { return }
        // Keep the session alive until the queued temporary workspaces have
        // been joined and removed. A stopped tab is removed from DocumentTabs
        // immediately, so a weak capture here could leak its extraction.
        packageWorkspaceDisposalTask = Task { @MainActor in
            await self.drainPackageWorkspaceDisposals()
        }
    }

    private func drainPackageWorkspaceDisposals() async {
        while !pendingPackageWorkspaceDisposals.isEmpty {
            await saveTask?.value
            let pending = pendingPackageWorkspaceDisposals.removeFirst()
            while saving || (pending.waitForIO && (busy || gitBusy || fileOperationCount > 0)) {
                try? await Task.sleep(for: .milliseconds(20))
            }
            await Task.detached(priority: nil) {
                LeonardoPackageTransport.discard(pending.workspace)
            }.value
        }
        packageWorkspaceDisposalTask = nil
    }
}
