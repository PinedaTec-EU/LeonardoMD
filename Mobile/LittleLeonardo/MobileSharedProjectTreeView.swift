import SwiftUI
import LeonardoSync

enum MobileSharedFileStatus: Equatable {
    case downloading, failed, availableOffline, offlinePending, cached, remote

    static func resolve(isDownloading: Bool, hasFailed: Bool, isAvailableOffline: Bool,
                        isRetained: Bool, isDownloaded: Bool) -> Self {
        if isDownloading { return .downloading }
        if hasFailed { return .failed }
        if isAvailableOffline { return .availableOffline }
        if isRetained { return .offlinePending }
        return isDownloaded ? .cached : .remote
    }
}
struct MobileSharedHostDisclosureRow: View {
    @Bindable var library: MobileLibrary
    let connection: MobileDirectConnection
    let descriptors: [SharedProjectDescriptor]
    let openFile: (SharedProjectDescriptor, RemoteFileEntry) -> Void

    var body: some View {
        DisclosureGroup {
            if descriptors.isEmpty {
                Text("No hay proyectos compartidos visibles en este dispositivo.")
                    .font(.subheadline).foregroundStyle(MobileClassic.secondary)
            }
            ForEach(descriptors) { descriptor in
                projectRow(descriptor)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title3).foregroundStyle(MobileClassic.heading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.hostDisplayName(connection.endpoint))
                        .font(.headline).foregroundStyle(MobileClassic.heading)
                    let visibleProjectIDs = connection.projectIDs.subtracting(library.projectLifecycle.deletedProjectIDs)
                    let pendingCount = visibleProjectIDs.subtracting(connection.ignoredProjectIDs)
                        .subtracting(connection.acceptedProjectIDs).count
                    let totalCount = visibleProjectIDs.count
                    Text(totalCount == 0 ? "Conexión activa" :
                         "\(totalCount) proyectos · \(pendingCount) por revisar")
                        .font(.caption).foregroundStyle(MobileClassic.secondary)
                }
            }
        }
        .accessibilityIdentifier("shared-host-\(connection.connectionID)")
        .listRowBackground(MobileClassic.paper)
    }

    @ViewBuilder private func projectRow(_ descriptor: SharedProjectDescriptor) -> some View {
        if connection.acceptedProjectIDs.contains(descriptor.id) {
            MobileSharedProjectTreeRow(library: library, connection: connection,
                descriptor: descriptor, newFilePaths: connection.newFilePaths[descriptor.id] ?? []) { entry in
                    openFile(descriptor, entry)
                }
        } else {
            MobileIncomingSharedProjectRow(library: library, connection: connection,
                                           descriptor: descriptor,
                                           ignored: connection.ignoredProjectIDs.contains(descriptor.id))
        }
    }

    private static func hostDisplayName(_ endpoint: URL) -> String {
        guard var host = endpoint.host, !host.isEmpty else { return "Mac conectado" }
        if host.lowercased().hasSuffix(".local") { host.removeLast(6) }
        host = host.replacingOccurrences(of: "-", with: " ")
        return host.prefix(1).uppercased() + String(host.dropFirst())
    }
}

private struct MobileIncomingSharedProjectRow: View {
    @Bindable var library: MobileLibrary
    let connection: MobileDirectConnection
    let descriptor: SharedProjectDescriptor
    let ignored: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(descriptor.name).font(.headline).foregroundStyle(MobileClassic.heading)
                Label(ignored ? "Ignorado" : "Proyecto nuevo",
                      systemImage: ignored ? "minus.circle" : "sparkle")
                    .font(.caption).foregroundStyle(MobileClassic.secondary)
            }
            Spacer(minLength: 4)
            if !ignored {
                Button("Añadir") { addProject() }
                    .buttonStyle(.borderedProminent).tint(MobileClassic.heading)
                    .foregroundStyle(MobileClassic.paper).disabled(library.connecting)
                    .accessibilityIdentifier("incoming-project-add-\(descriptor.id)")
                Button("Ignorar") {
                    library.ignoreSharedProject(connectionID: connection.connectionID, projectID: descriptor.id)
                }
                .buttonStyle(.bordered).disabled(library.connecting)
                .accessibilityIdentifier("incoming-project-ignore-\(descriptor.id)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("incoming-project-\(descriptor.id)")
    }

    private func addProject() {
        Task { await library.acceptSharedProject(connectionID: connection.connectionID, projectID: descriptor.id) }
    }
}

private struct MobileSharedProjectTreeRow: View {
    @Bindable var library: MobileLibrary
    let connection: MobileDirectConnection
    let descriptor: SharedProjectDescriptor
    let newFilePaths: Set<String>
    let open: (RemoteFileEntry) -> Void

    private var cached: CachedRemoteProject? {
        library.downloads.projects.first { $0.id == descriptor.id }
    }
    private var isKeepingProjectOffline: Bool { cached?.keepsFolder("") == true }
    private var hasRetainedFiles: Bool {
        guard let cached else { return false }
        return cached.catalogue.files.contains { cached.keeps($0.path) }
    }
    private var releasableFiles: [RemoteFileEntry] {
        guard let cached else { return [] }
        return cached.catalogue.files.filter { entry in
            !cached.keeps(entry.path) && cached.isDownloaded(entry)
        }
    }

    var body: some View {
        DisclosureGroup {
            if let cached {
                if cached.catalogue.files.isEmpty {
                    Text("Este proyecto no tiene ficheros compartidos.")
                        .font(.subheadline).foregroundStyle(MobileClassic.secondary)
                }
                ForEach(cached.catalogue.files.sorted {
                    $0.path.localizedStandardCompare($1.path) == .orderedAscending
                }) { entry in
                    fileRow(entry, project: cached)
                }
            } else {
                Text("Sincroniza para cargar los ficheros compartidos.")
                    .font(.subheadline).foregroundStyle(MobileClassic.secondary)
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(MobileClassic.heading).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.name).font(.headline).foregroundStyle(MobileClassic.heading)
                    Text(projectStatus)
                        .font(.caption).foregroundStyle(MobileClassic.secondary)
                    if isKeepingProjectOffline {
                        Text("Incluye los ficheros nuevos")
                            .font(.caption2).foregroundStyle(MobileClassic.secondary)
                    }
                }
                Spacer(minLength: 4)
                projectMenu
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("shared-project-\(descriptor.id)")
        .listRowBackground(MobileClassic.paper)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Eliminar de este dispositivo", role: .destructive) {
                Task { await library.deleteProject(descriptor.id) }
            }
            .disabled(library.connecting)
            .accessibilityIdentifier("delete-shared-project-\(descriptor.id)")
        }
    }

    private var projectStatus: String {
        guard let cached else { return "Solo remoto" }
        let entries = cached.catalogue.files
        guard !entries.isEmpty else { return "Sin ficheros" }
        let downloaded = entries.filter { cached.isDownloaded($0) }.count
        let active = entries.filter {
            library.downloads.downloading.contains(DownloadLibrary.key(id: descriptor.id, path: $0.path))
        }.count
        if active > 0 { return "Descargando \(active) de \(entries.count) ficheros" }
        let failed = entries.contains {
            library.downloads.failures[DownloadLibrary.key(id: descriptor.id, path: $0.path)] != nil
        }
        if failed { return "Error de descarga · se reintentará" }
        if isKeepingProjectOffline {
            let availability = entries.allSatisfy { cached.isAvailableOffline($0) }
                ? "Disponible sin conexión" : "Sin conexión pendiente"
            return "\(availability) · \(downloaded)/\(entries.count) ficheros"
        }
        return downloaded == 0 ? "Solo remoto" : "En caché · \(downloaded)/\(entries.count) ficheros"
    }

    private var projectMenu: some View {
        Menu {
            Button(isKeepingProjectOffline ? "Dejar de mantener sin conexión" : "Mantener sin conexión",
                   systemImage: isKeepingProjectOffline ? "pin.slash" : "pin") {
                if !isKeepingProjectOffline {
                    library.dismissNewFiles(connectionID: connection.connectionID, projectID: descriptor.id)
                }
                Task {
                    await library.setSharedContentOffline(id: descriptor.id, path: "", isFolder: true,
                                                          keep: !isKeepingProjectOffline)
                }
            }
            .disabled(cached == nil || library.connecting)
            Button("Liberar espacio local", systemImage: "externaldrive.badge.minus") {
                Task { await library.releaseSharedContent(id: descriptor.id, path: "", isFolder: true) }
            }
            .disabled(releasableFiles.isEmpty || library.connecting)
            if hasRetainedFiles {
                Text("Los ficheros fijados se conservan. Deja de mantenerlos sin conexión para liberarlos.")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(MobileClassic.heading)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Acciones de \(descriptor.name)")
        .accessibilityIdentifier("shared-project-actions-\(descriptor.id)")
    }

    private func fileRow(_ entry: RemoteFileEntry, project: CachedRemoteProject) -> some View {
        let isNew = newFilePaths.contains(entry.path)
        let retained = project.keeps(entry.path)
        let downloaded = project.isDownloaded(entry)
        return HStack(spacing: 10) {
            Button {
                if isNew {
                    library.dismissNewFile(connectionID: connection.connectionID,
                                           projectID: descriptor.id, path: entry.path)
                }
                open(entry)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text((entry.path as NSString).lastPathComponent)
                        .foregroundStyle(MobileClassic.heading)
                        .lineLimit(1)
                    if let parent = parentPath(entry.path) {
                        Text(parent).font(.caption2).foregroundStyle(MobileClassic.secondary).lineLimit(1)
                    }
                    if isNew {
                        Label("Archivo nuevo", systemImage: "sparkle")
                            .font(.caption2).foregroundStyle(MobileClassic.accent)
                    }
                    switch sharedFileStatus(project: project, entry: entry) {
                    case .downloading:
                        ProgressView("Descargando")
                            .font(.caption2).tint(MobileClassic.heading)
                            .accessibilityIdentifier("remote-file-downloading-\(descriptor.id)-\(entry.path)")
                    case .failed:
                        Label("Error de descarga · se reintentará", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel("Error de descarga; se reintentará al volver a abrir el fichero")
                            .accessibilityIdentifier("remote-file-download-failure-\(descriptor.id)-\(entry.path)")
                    case .availableOffline, .offlinePending, .cached, .remote:
                        Text(fileStatus(sharedFileStatus(project: project, entry: entry)))
                            .font(.caption2).foregroundStyle(MobileClassic.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shared-file-\(descriptor.id)-\(entry.path)")
            Menu {
                Button("Abrir", systemImage: "doc.text") {
                    if isNew {
                        library.dismissNewFile(connectionID: connection.connectionID,
                                               projectID: descriptor.id, path: entry.path)
                    }
                    open(entry)
                }
                Button(retained ? "Dejar de mantener sin conexión" : "Mantener sin conexión",
                       systemImage: retained ? "pin.slash" : "pin") {
                    if isNew {
                        library.dismissNewFile(connectionID: connection.connectionID,
                                               projectID: descriptor.id, path: entry.path)
                    }
                    Task { await library.setSharedContentOffline(id: descriptor.id, path: entry.path,
                                                                 isFolder: false, keep: !retained) }
                }
                Button("Liberar espacio local", systemImage: "externaldrive.badge.minus") {
                    Task { await library.releaseSharedContent(id: descriptor.id, path: entry.path, isFolder: false) }
                }
                .disabled(!downloaded || retained || library.connecting)
                if isNew {
                    Button("Ignorar novedad", systemImage: "xmark.circle") {
                        library.dismissNewFile(connectionID: connection.connectionID,
                                               projectID: descriptor.id, path: entry.path)
                    }
                    Text("No se descarga. Puedes abrirlo más adelante.")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MobileClassic.heading)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Acciones de \((entry.path as NSString).lastPathComponent)")
            .accessibilityIdentifier("shared-file-actions-\(descriptor.id)-\(entry.path)")
        }
        .padding(.vertical, 3)
        .listRowBackground(MobileClassic.paper)
    }

    private func sharedFileStatus(project: CachedRemoteProject, entry: RemoteFileEntry) -> MobileSharedFileStatus {
        let key = DownloadLibrary.key(id: descriptor.id, path: entry.path)
        return MobileSharedFileStatus.resolve(
            isDownloading: library.downloads.downloading.contains(key),
            hasFailed: library.downloads.failures[key] != nil,
            isAvailableOffline: project.isAvailableOffline(entry),
            isRetained: project.keeps(entry.path),
            isDownloaded: project.isDownloaded(entry))
    }

    private func fileStatus(_ status: MobileSharedFileStatus) -> String {
        switch status {
        case .availableOffline: "Disponible sin conexión"
        case .offlinePending: "Sin conexión pendiente"
        case .cached: "En caché"
        case .remote: "Solo remoto"
        case .downloading: "Descargando"
        case .failed: "Error de descarga · se reintentará"
        }
    }

    private func parentPath(_ path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "." ? nil : parent
    }
}
