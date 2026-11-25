import SwiftUI
import LeonardoCore
import LeonardoSync

struct WelcomeRemoteItemsView: View {
    let kind: FavoriteItem.Kind
    let showNonDocumentFiles: Bool

    @State private var destination: RemoteItem?
    @State private var managingProject = false
    @State private var managementError: String?
    private let controller = DesktopPeerController.shared

    var body: some View {
        let items = Self.remoteItems(kind: kind, controller: controller)
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                Text(L10n.text("Add a shared project in Synchronization preferences to see its remote items here."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            HStack(spacing: 8) {
                                remoteRow(item)
                                if item.path == nil, !InstanceRuntime.isAdditional,
                                   let project = controller.downloads.projects.first(where: { $0.id == item.projectID }) {
                                    projectMenu(project)
                                }
                            }
                        }
                    }
                }
                .frame(height: CGFloat(min(items.count, 5) * 52 - 4))
                .id(kind)
            }
        }
        .alert(L10n.text("Synchronization error"), isPresented: Binding(
            get: { managementError != nil },
            set: { if !$0 { managementError = nil } }
        )) {
            Button(L10n.text("OK")) { managementError = nil }
        } message: {
            Text(managementError ?? "")
        }
        .sheet(item: $destination) { item in
            DesktopDownloadBrowser(library: controller.downloads, projectID: item.projectID,
                                   initialPath: item.path, showNonDocumentFiles: showNonDocumentFiles)
        }
    }

    static func remoteItems(kind: FavoriteItem.Kind, controller: DesktopPeerController) -> [RemoteItem] {
        let catalogues = Dictionary(uniqueKeysWithValues: controller.downloads.projects.map { ($0.id, $0) })
        return controller.connections.flatMap { connection in
            let host = controller.reviewStore.hostName(for: connection)
            return controller.acceptedProjectDescriptors(for: connection).flatMap { descriptor -> [RemoteItem] in
                let id = DesktopPeerController.downloadID(connectionID: connection.id, projectID: descriptor.id)
                guard let project = catalogues[id] else { return [] }
                if kind == .project {
                    return [RemoteItem(projectID: id, title: descriptor.name, detail: host)]
                }
                return documentItems(in: project, projectName: descriptor.name, host: host)
            }
        }.sorted { lhs, rhs in
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            return titleOrder == .orderedSame
                ? lhs.detail.localizedStandardCompare(rhs.detail) == .orderedAscending
                : titleOrder == .orderedAscending
        }
    }

    private static func documentItems(in project: CachedRemoteProject, projectName: String, host: String) -> [RemoteItem] {
        let deniedPaths = project.deniedPaths ?? []
        return project.catalogue.files.compactMap { entry in
            let path = entry.path as NSString
            guard !deniedPaths.contains(entry.path),
                  LeonardoProjectFileVisibility.isSupportedDocumentExtension(path.pathExtension) else {
                return nil
            }
            let detail = [projectName, path.deletingLastPathComponent, host].filter { !$0.isEmpty }.joined(separator: " · ")
            return RemoteItem(projectID: project.id, title: path.lastPathComponent, detail: detail, path: entry.path)
        }
    }

    private func remoteRow(_ item: RemoteItem) -> some View {
        Button {
            destination = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.path == nil ? "folder" : "doc.text")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).lineLimit(1)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 6)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.detail)
    }

    private func projectMenu(_ project: CachedRemoteProject) -> some View {
        let keptOffline = project.retention.contains { $0.isFolder && $0.path.isEmpty && $0.keep }
        return Menu {
            Button(L10n.text(keptOffline ? "Stop keeping project offline" : "Keep project offline"),
                   systemImage: keptOffline ? "pin.slash" : "pin") {
                updateProjectCache {
                    await controller.downloads.retain(id: project.id, path: "", isFolder: true, keep: !keptOffline)
                }
            }
            Button(L10n.text("Release temporary project downloads"), systemImage: "cloud") {
                updateProjectCache {
                    await controller.downloads.release(id: project.id, path: "", isFolder: true)
                }
            }
            .disabled(!project.downloads.keys.contains { !project.keeps($0) })
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(managingProject || !controller.storageAuthorized)
        .help(L10n.text("Manage remote project"))
        .accessibilityLabel(L10n.format("Manage remote project: %@", project.descriptor.name))
        .accessibilityIdentifier("welcome-remote-manage-\(project.id)")
    }

    private func updateProjectCache(_ operation: @escaping () async -> Void) {
        guard !managingProject else { return }
        managingProject = true
        Task {
            defer { managingProject = false }
            controller.downloads.error = nil
            await operation()
            managementError = controller.downloads.error
        }
    }

    struct RemoteItem: Identifiable {
        let projectID: UUID
        let title: String
        let detail: String
        var path: String?
        var id: String { projectID.uuidString + ":" + (path ?? "") }
    }
}
