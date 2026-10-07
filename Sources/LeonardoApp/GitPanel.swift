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
                Label("Control de versiones", systemImage: "arrow.triangle.branch").font(.title2.bold())
                Spacer()
                if session.gitBusy { ProgressView().controlSize(.small) }
                Button("Listo") { dismiss() }
            }
            Text(session.gitSummary).foregroundStyle(.secondary)
            if session.gitStatus?.state == .noRepository {
                Text("Este proyecto aún no tiene repositorio Git.")
                Button("Inicializar Git") { session.performGit(.initialize) }.buttonStyle(PremiumButtonStyle(prominent: true))
            } else {
                HStack {
                    Button("Fetch") { session.performGit(.fetch) }
                    Button("Pull") { session.performGit(.pull) }
                    Button("Push") { session.performGit(.push) }
                    Spacer()
                    Button("Actualizar") { Task { await session.refreshGit() } }
                }
                Text("Cambios").font(.headline)
                List(session.gitStatus?.changes ?? []) { change in
                    HStack {
                        Toggle(isOn: Binding(get: { selected.contains(change.path) }, set: { value in
                            if value { selected.insert(change.path) } else { selected.remove(change.path) }
                        })) { Text(change.path) }.toggleStyle(.checkbox)
                        if change.isStaged { Text("Staged").font(.caption).foregroundStyle(.secondary) }
                        if change.status == .conflicted {
                            Button("Abrir conflicto") {
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
                    Button("Stage seleccionados") { session.performGit(.stage(Array(selected))) }.disabled(selected.isEmpty)
                    Button("Stage todos") { session.performGit(.stageAll) }
                }
                HStack {
                    TextField("Mensaje del commit", text: $message)
                    Button("Commit") { session.performGit(.commit(message)); message = "" }.disabled(message.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Divider()
                Text("Historial reciente").font(.headline)
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
            Text("Se usan Git y las credenciales configuradas en tu Mac. Pull requiere el árbol limpio; los conflictos se resuelven manualmente.")
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
    func refreshGit() async {
        guard gitEnabled, let git else { gitSummary = "Git desactivado"; return }
        do {
            let status = try await git.status()
            gitStatus = status
            if status.state == .noRepository { gitSummary = "Inicializar Git"; gitHistory = []; return }
            gitSummary = "\(status.branch ?? "HEAD") · \(status.changes.count) cambios · ↑\(status.ahead) ↓\(status.behind)"
            if status.hasConflicts { gitSummary += " · Conflicto" }
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
                errorMessage = "Git tiene cambios locales. Haz commit o resuélvelos en Git antes de sincronizar."
            } catch GitError.mergeConflict(let paths) {
                errorMessage = "Conflictos en: " + paths.joined(separator: ", ")
                await refreshGit()
            } catch { report(error) }
        }
    }
}
