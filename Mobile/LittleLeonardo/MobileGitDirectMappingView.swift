import SwiftUI
import LeonardoSync

struct MobileGitDirectMappingOption: Equatable, Sendable, Identifiable {
    let connectionID: UUID
    let source: SharedProjectDescriptor
    let connectionLabel: String

    var id: String { "\(connectionID.uuidString):\(source.id.uuidString)" }
}

/// Lets the user associate one mobile Git project with one explicitly granted
/// desktop source project. The source UUID is displayed only as an audit aid;
/// choosing a row is the association action.
struct MobileGitDirectMappingView: View {
    let library: MobileLibrary
    let projectID: UUID
    @State private var options: [MobileGitDirectMappingOption] = []
    @State private var busy = false
    @State private var operation: Task<Void, Never>?
    @State private var notificationStatus: String?

    private var project: OfflineProject? { library.projects.first { $0.id == projectID } }
    private var mapping: MobileGitDirectMapping? { library.directGitMappings[projectID] }

    var body: some View {
        Form {
            Section {
                Text("Después de publicar cambios Git, Little Leonardo puede avisar al LeonardoMD autorizado para que revise la reconciliación.")
                    .font(.caption)
                Text("El proyecto Git y el proyecto compartido de LeonardoMD tienen identificadores distintos. Elige explícitamente la carpeta autorizada.")
                    .font(.caption)
            }

            Section("Proyecto Git") {
                Text(project?.name ?? "Proyecto")
                if let project {
                    Text("Carpeta: \(project.scope.folder.isEmpty ? "/" : project.scope.folder)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Proyectos autorizados") {
                if options.isEmpty {
                    Text("No hay proyectos autorizados que cubran esta carpeta. Comprueba la conexión directa y actualiza la lista.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(options) { option in
                        Button {
                            operation?.cancel()
                            operation = Task {
                                busy = true
                                defer { busy = false }
                                _ = await library.setDirectGitMapping(
                                    gitProjectID: projectID,
                                    connectionID: option.connectionID,
                                    sourceProjectID: option.source.id)
                                await reload()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.source.name)
                                    Text(option.source.id.uuidString)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(option.connectionLabel)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if mapping?.connectionID == option.connectionID,
                                   mapping?.sourceProjectID == option.source.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }.disabled(busy)
                    }
                }
            }

            if mapping != nil {
                Section {
                    Button("Desvincular", role: .destructive) {
                        operation?.cancel()
                        operation = Task {
                            busy = true
                            defer { busy = false }
                            _ = await library.removeDirectGitMapping(gitProjectID: projectID)
                            await reload()
                        }
                    }.disabled(busy)
                }
            }

            if mapping != nil, let project, project.publication == .sent {
                Section("Aviso a LeonardoMD") {
                    Text("La publicación Git ya está confirmada. Puedes reintentar el aviso sin volver a subirla.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Reintentar aviso") {
                        operation?.cancel()
                        operation = Task {
                            busy = true
                            defer { busy = false }
                            switch await library.notifyGitReconciliation(for: project) {
                            case .delivered:
                                notificationStatus = "Aviso enviado"
                            case .failed:
                                notificationStatus = "No se pudo enviar el aviso; la publicación Git se conserva"
                            case .notConfigured:
                                notificationStatus = "No hay una asociación autorizada"
                            }
                        }
                    }.disabled(busy)
                    if let notificationStatus {
                        Text(notificationStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Aviso de reconciliación")
        .toolbar {
            Button("Actualizar", systemImage: "arrow.clockwise") {
                operation?.cancel()
                operation = Task { await reload() }
            }.disabled(busy)
        }
        .task { await reload() }
        .onDisappear { operation?.cancel() }
    }

    private func reload() async {
        options = await library.directGitMappingOptions(for: projectID)
    }
}
