#if os(macOS)
import SwiftUI
import LeonardoCore

struct GitPanel: View {
    @Bindable var session: AppSession
    @Bindable var desktopSync: DesktopSyncController
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var message = ""
    @State private var controller: DesktopGitController?

    init(session: AppSession, desktopSync: DesktopSyncController = .shared) {
        self.session = session
        self.desktopSync = desktopSync
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L10n.text("Version control"), systemImage: "arrow.triangle.branch").font(.title2.bold())
                Spacer()
                if session.gitBusy || controller?.busy == true { ProgressView().controlSize(.small) }
                Button(L10n.text("Done")) { dismiss() }
            }
            Text(session.gitSummary).foregroundStyle(.secondary)
            if session.gitStatus?.state == .noRepository {
                Text(L10n.text("This project does not have a Git repository yet."))
                Button(L10n.text("Initialize Git")) { session.performGit(.initialize) }
                    .buttonStyle(PremiumButtonStyle(prominent: true))
            } else {
                localGitControls
                Divider()
                if let controller {
                    DesktopGitPublicationSection(controller: controller)
                } else {
                    Text(L10n.text("Preparing Git publication review…")).foregroundStyle(.secondary)
                }
            }
            Text(L10n.text("Git fetch uses the configured credential helper and transfers only filtered Little Leonardo publication refs. The index and staged changes stay local."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .padding(24)
        .frame(width: 820, height: 700)
        .disabled(session.gitBusy || controller?.busy == true)
        .task {
            await session.refreshGit()
            await prepareController()
        }
    }

    private var localGitControls: some View {
        Group {
            HStack {
                Button(L10n.text("Fetch")) { session.performGit(.fetch) }
                Button(L10n.text("Pull")) { session.performGit(.pull) }
                Button(L10n.text("Push")) { session.performGit(.push) }
                Spacer()
                Button(L10n.text("Refresh")) { Task { await session.refreshGit(); await controller?.refreshRemotes() } }
            }
            Text(L10n.text("Changes")).font(.headline)
            List(session.gitStatus?.changes ?? []) { change in
                HStack {
                    Toggle(isOn: Binding(get: { selected.contains(change.path) }, set: { value in
                        if value { selected.insert(change.path) } else { selected.remove(change.path) }
                    })) { Text(change.path) }.toggleStyle(.checkbox)
                    if change.isStaged { Text(L10n.text("Staged")).font(.caption).foregroundStyle(.secondary) }
                    if change.status == .conflicted {
                        Button(L10n.text("Open conflict")) {
                            if let root = session.projectURL {
                                Task {
                                    let url = root.appendingPathComponent(change.path)
                                    await session.openDocument(url)
                                    if session.documentURL == url { session.mode = .edit }
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }.frame(minHeight: 100, maxHeight: 170)
            HStack {
                Button(L10n.text("Stage selected")) { session.performGit(.stage(Array(selected))) }.disabled(selected.isEmpty)
                Button(L10n.text("Stage all")) { session.performGit(.stageAll) }
            }
            HStack {
                TextField(L10n.text("Commit message"), text: $message)
                Button(L10n.text("Commit")) { session.performGit(.commit(message)); message = "" }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(L10n.text("Recent history")).font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.gitHistory) { commit in
                        HStack {
                            Text(commit.shortHash).font(.system(.caption, design: .monospaced))
                            Text(commit.subject).lineLimit(1)
                            Spacer()
                            Text(commit.author).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(height: 90)
        }
    }

    private func prepareController() async {
        guard controller == nil, let root = session.projectURL else { return }
        let stateRoot = AppSession.preferencesURL.deletingLastPathComponent()
            .appendingPathComponent("GitIntegration", isDirectory: true)
        let created = DesktopGitController(
            projectRoot: root, stateRoot: stateRoot,
            buffers: desktopSync.buffers)
        controller = created
        await created.refreshRemotes()
        await created.recover()
    }
}

private struct DesktopGitPublicationSection: View {
    @Bindable var controller: DesktopGitController
    @State private var showingReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("Little Leonardo publications")).font(.headline)
                Spacer()
                Button(L10n.text("Refresh remotes")) { Task { await controller.refreshRemotes() } }
            }
            if controller.remotes.isEmpty {
                Text(L10n.text("No Git remotes are configured for this project.")).foregroundStyle(.secondary)
            } else {
                HStack {
                    Picker(L10n.text("Remote"), selection: Binding(get: { controller.selectedRemote ?? "" }, set: { controller.selectedRemote = $0 })) {
                        ForEach(controller.remotes) { remote in
                            Text(remote.name).tag(remote.name)
                        }
                    }
                    Button(L10n.text("Find publications")) { Task { await controller.fetchPublications() } }
                }
                if !controller.branches.isEmpty {
                    Text(L10n.text("Published branches")).font(.subheadline.bold())
                    Picker(L10n.text("Branch"), selection: Binding(get: { controller.selectedBranchID ?? "" }, set: { controller.selectedBranchID = $0 })) {
                        ForEach(controller.branches, id: \.name) { branch in
                            Text("\(branch.deviceID.uuidString.prefix(8)) · \(branch.commitID.prefix(12))")
                                .tag(branch.name)
                        }
                    }
                    HStack {
                        Button(L10n.text("Inspect metadata")) { Task { await controller.inspectSelectedBranch() } }
                        if let metadata = controller.proposalMetadata {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metadata.branch.name)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                Text(L10n.format("Project ID: %@", metadata.projectID.uuidString))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(L10n.format("Device ID: %@", metadata.deviceID.uuidString))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(L10n.format("Proposal commit: %@", metadata.branch.commitID))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(L10n.format("Base %@", String(metadata.baseRevision.prefix(12))))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(L10n.format("Scope: %@", metadata.scope.folder.isEmpty ? L10n.text("Repository root") : metadata.scope.folder))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(L10n.format("Publication purpose: %@", L10n.text(metadata.purpose.desktopLocalizedLabelKey)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button(L10n.text("Approve folder and review")) {
                                Task {
                                    await controller.approveScope()
                                    showingReview = controller.review != nil
                                }
                            }
                        }
                    }
                } else {
                    Text(L10n.text("Fetch publications to discover Little Leonardo branches.")).foregroundStyle(.secondary)
                }
            }
            if controller.publicationPending {
                HStack {
                    Label(L10n.text("Git integration publication pending"), systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(L10n.text("Retry publication")) {
                        Task { await controller.retryPublication() }
                    }
                }
            }
            if let error = controller.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .sheet(isPresented: Binding(get: { controller.review != nil || showingReview }, set: { presented in
            showingReview = presented
            if !presented { controller.cancelReview() }
        })) {
            if let review = controller.review {
                DesktopGitReviewView(controller: controller, value: review)
            }
        }
    }
}

enum GitAction {
    case initialize, fetch, pull, push, stage([String]), stageAll, commit(String)
    var name: String {
        switch self {
        case .initialize: "initialize"
        case .fetch: "fetch"
        case .pull: "pull"
        case .push: "push"
        case .stage, .stageAll: "stage"
        case .commit: "commit"
        }
    }
}

extension AppSession {
    var gitSummary: String {
        guard gitEnabled else { return L10n.text("Git disabled") }
        guard let status = gitStatus else { return "Git" }
        if status.state == .noRepository { return L10n.text("Initialize Git") }
        let summary = L10n.format("%@ · %d changes · ↑%d ↓%d", status.branch ?? "HEAD", status.changes.count, status.ahead, status.behind)
        return summary + (status.hasConflicts ? L10n.text(" · Conflict") : "")
    }

    func refreshGit() async {
        guard gitEnabled, let git else { return }
        do {
            let status = try await git.status()
            gitStatus = status
            if status.state == .noRepository { gitHistory = []; return }
            gitHistory = (try? await git.history(limit: 20)) ?? []
        } catch { report(error) }
    }

    func performGit(_ action: GitAction) {
        guard !isSyncSuspended, !gitBusy, let git else { return }
        gitBusy = true
        logger.info("git_operation_started operation=\(action.name, privacy: .public)")
        Task {
            defer { gitBusy = false }
            guard await prepareNavigation(allowGitOperation: true) else { return }
            do {
                switch action {
                case .initialize: _ = try await git.initialize()
                case .fetch: _ = try await git.fetch()
                case .pull: _ = try await git.pull()
                case .push: _ = try await git.push()
                case .stage(let paths): _ = try await git.stage(paths: paths)
                case .stageAll: _ = try await git.stageAll()
                case .commit(let message): _ = try await git.commit(message: message)
                }
                logger.info("git_operation_completed operation=\(action.name, privacy: .public)")
                await refreshGit()
                await refreshTree()
                await checkExternalChanges()
            } catch GitError.workingTreeDirty {
                errorMessage = L10n.text("Git has local changes. Commit or resolve them in Git before syncing.")
            } catch GitError.mergeConflict(let paths) {
                errorMessage = L10n.text("Conflicts in: ") + paths.joined(separator: ", ")
                await refreshGit()
            } catch { report(error) }
        }
    }
}
#endif
