#if os(macOS)
import SwiftUI
import LeonardoCore

struct GitPanel: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var message = ""

    init(session: AppSession) {
        self.session = session
    }

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
                Button(L10n.text("Initialize Git")) { session.performGit(.initialize) }
                    .buttonStyle(PremiumButtonStyle(prominent: true))
            } else {
                localGitControls

            }
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .padding(24)
        .frame(width: 820, height: 700)
        .disabled(session.gitBusy)
        .task {
            await session.refreshGit()
        }
    }

    private var localGitControls: some View {
        Group {
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

}
#endif
