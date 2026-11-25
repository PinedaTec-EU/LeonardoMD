import SwiftUI
import LeonardoCore
import LeonardoSync

struct WelcomeRemoteItemsView: View {
    let kind: FavoriteItem.Kind
    let showNonDocumentFiles: Bool

    @State private var destination: RemoteItem?
    private let controller = DesktopPeerController.shared

    var body: some View {
        let items = remoteItems
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                Text(L10n.text("Add a shared project in Synchronization preferences to see its remote items here."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            remoteRow(item)
                        }
                    }
                }
                .frame(height: CGFloat(min(items.count, 5) * 52 - 4))
                .id(kind)
            }
        }
        .sheet(item: $destination) { item in
            DesktopDownloadBrowser(library: controller.downloads, projectID: item.projectID,
                                   initialPath: item.path, showNonDocumentFiles: showNonDocumentFiles)
        }
    }

    private var remoteItems: [RemoteItem] {
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

    private func documentItems(in project: CachedRemoteProject, projectName: String, host: String) -> [RemoteItem] {
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

    private struct RemoteItem: Identifiable {
        let projectID: UUID
        let title: String
        let detail: String
        var path: String?
        var id: String { projectID.uuidString + ":" + (path ?? "") }
    }
}
