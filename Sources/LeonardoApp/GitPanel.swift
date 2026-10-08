import SwiftUI
import LeonardoCore

struct GitPanel: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L10n.text("Version control"), systemImage: "arrow.triangle.branch").font(.title2.bold())
                Spacer()
                if session.gitBusy { ProgressView().controlSize(.small) }
                Button(L10n.text("Done")) { dismiss() }
            }
            Text(session.gitSummary).foregroundStyle(.secondary)
            if session.gitStatus?.state == .noRepository {
                Text(L10n.text("This project does not have a Git repository yet."))
                Button(L10n.text("Initialize Git")) { session.performGit(.initialize) }.buttonStyle(PremiumButtonStyle(prominent: true))
            } else {
                HStack {
                    Button(L10n.text("Fetch")) { session.performGit(.fetch) }
                    Button(L10n.text("Pull")) { session.performGit(.pull) }
                    Button(L10n.text("Push")) { session.performGit(.push) }
                    Spacer()
                    Button(L10n.text("Refresh")) { Task { await session.refreshGit() } }
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
                }.frame(minHeight: 120)
                HStack {
                    Button(L10n.text("Stage selected")) { session.performGit(.stage(Array(selected))) }.disabled(selected.isEmpty)
                    Button(L10n.text("Stage all")) { session.performGit(.stageAll) }
                }
                HStack {
                    TextField(L10n.text("Commit message"), text: $message)
                    Button(L10n.text("Commit")) { session.performGit(.commit(message)); message = "" }.disabled(message.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Divider()
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
                }.frame(height: 130)
            }
            Text(L10n.text("Uses Git and credentials configured on your Mac. Pull requires a clean working tree; resolve conflicts manually."))
                .font(.caption).foregroundStyle(.secondary)
        }.buttonStyle(PremiumButtonStyle(compact: true)).padding(24).frame(width: 720, height: 620)
            .disabled(session.gitBusy)
            .task { await session.refreshGit() }
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
        guard !gitBusy, let git else { return }
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
