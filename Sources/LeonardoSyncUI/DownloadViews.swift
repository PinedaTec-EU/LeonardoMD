import SwiftUI
import LeonardoSync

/// Identical retention and cache controls on both consuming platforms.
public struct SyncCacheSettingsView: View {
    @Bindable var library: DownloadLibrary
    let spanish: Bool
    @State private var limitDraft = ""
    @FocusState private var editingLimit: Bool
    public init(library: DownloadLibrary, spanish: Bool = false) { self.library = library; self.spanish = spanish }
    private func t(_ en: String, _ es: String) -> String { spanish ? es : en }
    public var body: some View {
        Section(t("Storage and cache", "Almacenamiento y caché")) {
            LabeledContent(t("Temporary cache", "Caché temporal"), value: bytes(library.usage.temporaryBytes))
                .accessibilityIdentifier("temporary-cache-usage")
            LabeledContent(t("Kept offline (separate)", "Sin conexión (separado)"), value: bytes(library.usage.offlineBytes))
                .accessibilityIdentifier("offline-storage-usage")
            LabeledContent(t("Pending offline files", "Archivos offline pendientes"), value: String(library.usage.pendingOfflineFiles))
                .accessibilityIdentifier("pending-offline-files")
            LabeledContent {
                TextField("MiB", text: $limitDraft)
                    .multilineTextAlignment(.trailing).frame(minWidth: 64, idealWidth: 84, maxWidth: 104)
                    .focused($editingLimit).submitLabel(.done).onSubmit(applyLimit)
                    .accessibilityIdentifier("temporary-cache-limit")
            } label: {
                Text(t("Temporary limit (MiB)", "Límite temporal (MiB)"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(t("Apply cache limit", "Aplicar límite de caché"), action: applyLimit)
                .disabled(requestedLimitBytes == nil || requestedLimitBytes == library.usage.limitBytes)
                .accessibilityIdentifier("apply-cache-limit")
            if !limitDraft.isEmpty, requestedLimitBytes == nil {
                Text(t("Enter a nonnegative whole number of MiB.", "Introduce un número entero de MiB, igual o mayor que cero."))
                    .font(.caption).foregroundStyle(.red)
            }
            Button(t("Clear temporary cache", "Limpiar caché temporal")) { Task { await library.clearTemporary() } }
                .accessibilityIdentifier("clear-temporary-cache")
            Text(t("Offline files do not count toward this limit. Clearing cache never removes offline files or editable copies.",
                   "Los archivos offline no cuentan para este límite. Limpiar la caché conserva los archivos offline y las copias editables."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(library.projects) { project in
                ForEach(project.retention.filter(\.keep)) { rule in
                    HStack {
                        Label(project.descriptor.name + " / " + (rule.path.isEmpty ? "/" : rule.path),
                              systemImage: rule.isFolder ? "folder" : "doc")
                        Spacer()
                        Button(t("Stop keeping offline", "Dejar de mantener sin conexión")) {
                            Task { await library.retain(id: project.id, path: rule.path, isFolder: rule.isFolder, keep: false) }
                        }
                    }
                }
            }
            if let error = library.error { Text(error).foregroundStyle(.red) }
        }.onAppear { limitDraft = String(library.usage.limitBytes / Self.bytesPerMiB) }
        .onChange(of: library.usage.limitBytes) { _, value in
            if !editingLimit { limitDraft = String(value / Self.bytesPerMiB) }
        }
    }
    private static let bytesPerMiB = 1_024 * 1_024
    private var requestedLimitBytes: Int? {
        guard let value = Int(limitDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
              value >= 0, value <= Int.max / Self.bytesPerMiB else { return nil }
        return value * Self.bytesPerMiB
    }
    private func applyLimit() {
        guard let bytes = requestedLimitBytes else { return }
        editingLimit = false
        Task { await library.setLimit(bytes: bytes) }
    }
    private func bytes(_ count: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file) }
}

public struct SyncCatalogueView: View {
    @Bindable var library: DownloadLibrary
    let projectID: UUID
    let spanish: Bool
    let rowBackground: Color?
    let open: (RemoteFileEntry) -> Void
    public init(library: DownloadLibrary, projectID: UUID, spanish: Bool = false, rowBackground: Color? = nil, open: @escaping (RemoteFileEntry) -> Void) {
        self.library = library; self.projectID = projectID; self.spanish = spanish; self.rowBackground = rowBackground; self.open = open
    }
    private var project: CachedRemoteProject? { library.projects.first { $0.id == projectID } }
    private func t(_ en: String, _ es: String) -> String { spanish ? es : en }
    public var body: some View {
        if let project {
            VStack(alignment: .leading) {
                Text(t("Files download when opened. Use the context menu to keep files or folders offline.",
                       "Los archivos se descargan al abrirlos. Usa el menú contextual para mantener archivos o carpetas sin conexión."))
                    .font(.caption).foregroundStyle(.secondary)
                List {
                    folderRow(path: "", project: project)
                    ForEach(project.catalogue.folders, id: \.self) { folder in folderRow(path: folder, project: project) }
                    ForEach(project.catalogue.files) { entry in
                        Button { open(entry) } label: {
                            HStack {
                                Label(entry.path, systemImage: "doc")
                                Spacer()
                                status(paths: [entry], project: project)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityIdentifier("download-file-" + entry.path)
                        .contextMenu { actions(path: entry.path, isFolder: false, project: project) }
                        .listRowBackground(rowBackground)
                    }
                }
            }.navigationTitle(project.descriptor.name)
        } else { Text(t("Project unavailable", "Proyecto no disponible")) }
    }
    private func folderRow(path: String, project: CachedRemoteProject) -> some View {
        let entries = project.catalogue.files.filter { path.isEmpty || $0.path.hasPrefix(path + "/") }
        return HStack {
            Label(path.isEmpty ? project.descriptor.name : path, systemImage: "folder")
            Spacer()
            status(paths: entries, project: project)
        }.contextMenu { actions(path: path, isFolder: true, project: project) }
            .accessibilityIdentifier("download-folder-" + path).listRowBackground(rowBackground)
    }
    @ViewBuilder private func status(paths: [RemoteFileEntry], project: CachedRemoteProject) -> some View {
        let retained = paths.filter { project.keeps($0.path) }.count
        let downloaded = paths.filter { project.isDownloaded($0) }.count
        let active = paths.contains { library.downloading.contains(DownloadLibrary.key(id: projectID, path: $0.path)) }
        let failed = paths.contains { library.failures[DownloadLibrary.key(id: projectID, path: $0.path)] != nil }
        if active { ProgressView().controlSize(.small).accessibilityLabel(t("Downloading", "Descargando")) }
        if failed { Image(systemName: "exclamationmark.triangle").accessibilityLabel(t("Download failed; retries automatically", "Error de descarga; reintento automático")) }
        Text(statusText(paths: paths, project: project, retained: retained, downloaded: downloaded))
            .font(.caption).foregroundStyle(.secondary)
        if paths.count > 1 { Text("\(downloaded)/\(paths.count)").font(.caption.monospacedDigit()) }
    }
    private func statusText(paths: [RemoteFileEntry], project: CachedRemoteProject, retained: Int, downloaded: Int) -> String {
        if retained == paths.count && retained > 0 {
            return paths.allSatisfy { project.isAvailableOffline($0) }
                ? t("Available offline", "Disponible sin conexión") : t("Offline pending", "Offline pendiente")
        }
        if retained > 0 { return t("Partly kept offline", "Offline parcial") }
        return downloaded == 0 ? t("Remote only", "Solo remoto") : t("Cached", "En caché")
    }
    @ViewBuilder private func actions(path: String, isFolder: Bool, project: CachedRemoteProject) -> some View {
        let entries = project.catalogue.files.filter { isFolder ? path.isEmpty || $0.path.hasPrefix(path + "/") : $0.path == path }
        let kept = isFolder ? project.keepsFolder(path) : project.keeps(path)
        Button(kept ? t("Stop keeping offline", "Dejar de mantener sin conexión") : t("Keep offline", "Mantener sin conexión"),
               systemImage: kept ? "pin.slash" : "pin") {
            Task { await library.retain(id: projectID, path: path, isFolder: isFolder, keep: !kept) }
        }
        Button(t("Release local space", "Liberar espacio local"), systemImage: "cloud") {
            Task { await library.release(id: projectID, path: path, isFolder: isFolder) }
        }.disabled(!entries.contains { !project.keeps($0.path) && project.isDownloaded($0) })
    }
}
