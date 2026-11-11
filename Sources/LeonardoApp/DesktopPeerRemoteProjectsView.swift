import SwiftUI
import LeonardoSync
import LeonardoSyncUI

struct DesktopPeerRemoteProjectsView: View {
    @Bindable var controller: DesktopPeerController
    @State private var selectedConnectionID: UUID?
    @State private var browsingID: UUID?
    @State private var browsingPath: String?
    @State private var renamingConnection: DesktopPeerConnection?
    @State private var hostNameDraft = ""

    private var connections: [DesktopPeerConnection] {
        controller.connections.sorted {
            controller.reviewStore.hostName(for: $0).localizedStandardCompare(
                controller.reviewStore.hostName(for: $1)) == .orderedAscending
        }
    }

    private var selectedConnection: DesktopPeerConnection? {
        connections.first(where: { $0.id == selectedConnectionID }) ?? connections.first
    }

    var body: some View {
        Group {
            if connections.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("No other computers are connected yet."))
                    Text(L10n.text("Connect to another Mac to browse projects it shares."))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    hostList
                        .frame(width: 215, alignment: .topLeading)
                    Divider()
                    if let connection = selectedConnection {
                        hostDetail(connection)
                    }
                }
                .frame(minHeight: 360, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .sheet(isPresented: Binding(get: { browsingID != nil }, set: { if !$0 { browsingID = nil; browsingPath = nil } })) {
            if let id = browsingID {
                DesktopDownloadBrowser(library: controller.downloads, projectID: id, initialPath: browsingPath)
            }
        }
        .sheet(item: $renamingConnection) { connection in
            renameSheet(connection)
        }
    }

    private var hostList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(connections) { connection in
                Button {
                    selectedConnectionID = connection.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(controller.reviewStore.hostName(for: connection), systemImage: "laptopcomputer")
                            .lineLimit(1).truncationMode(.middle)
                        Text(connection.revoked ? L10n.text("Revoked")
                             : (connection.comparisonCode == nil ? L10n.text("Linked") : L10n.text("Awaiting approval")))
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.leading, 23)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8).padding(.horizontal, 9)
                    .background(selectedConnection?.id == connection.id ? Color.accentColor.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("remote-host-\(connection.id.uuidString)")
            }
            Spacer(minLength: 0)
        }
    }

    private func hostDetail(_ connection: DesktopPeerConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.reviewStore.hostName(for: connection)).font(.title3.weight(.semibold))
                    Text(connection.endpoint.absoluteString).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Menu {
                    Button(L10n.text("Rename computer…"), systemImage: "pencil") {
                        hostNameDraft = controller.reviewStore.hostName(for: connection)
                        renamingConnection = connection
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").imageScale(.large)
                }
                .menuStyle(.borderlessButton)
                if !connection.revoked {
                    Button(L10n.text("Update list"), systemImage: "arrow.clockwise") {
                        Task { await controller.refresh(connection.id) }
                    }
                    .disabled(!controller.helper.online || controller.busy)
                }
            }

            if let code = connection.comparisonCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text(code).font(.title2.monospaced()).textSelection(.enabled)
                    Text(L10n.text("Approve this code on the other Mac before browsing its projects."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
            }

            if connection.revoked {
                Text(L10n.text("This connection has been revoked."))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        newProjects(connection)
                        newFiles(connection)
                        acceptedProjects(connection)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func newProjects(_ connection: DesktopPeerConnection) -> some View {
        let projects = (controller.available[connection.id] ?? []).filter {
            !controller.reviewStore.acceptsProject(connectionID: connection.id, projectID: $0.id)
                && !controller.reviewStore.ignoredProject(connectionID: connection.id, projectID: $0.id)
        }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.text("New projects to review"), count: projects.count)
            if projects.isEmpty {
                Text(controller.available[connection.id] == nil
                     ? L10n.text("Update the list to check for new projects.")
                     : L10n.text("No new projects from this computer."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(projects) { project in
                    HStack(spacing: 9) {
                        Image(systemName: "folder").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name).font(.headline)
                            Text(String(format: L10n.text("Shared by %@"), controller.reviewStore.hostName(for: connection)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(L10n.text("Add project")) {
                            Task { await controller.addRemoteProject(connectionID: connection.id, projectID: project.id) }
                        }.disabled(!controller.helper.online || controller.busy)
                        Button(L10n.text("Ignore")) {
                            controller.ignoreRemoteProject(connectionID: connection.id, projectID: project.id)
                        }
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
                Text(L10n.text("Adding a project saves a remote reference. Its files stay remote until opened or kept offline."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func newFiles(_ connection: DesktopPeerConnection) -> some View {
        let notices = fileNotices(for: connection)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.text("New files"), count: notices.count)
            if notices.isEmpty {
                Text(L10n.text("New files in added projects will appear here after the next update."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(notices, id: \.id) { notice in
                    HStack(spacing: 9) {
                        Image(systemName: "doc").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(notice.entry.path).font(.headline).lineLimit(1).truncationMode(.middle)
                            Text(String(format: L10n.text("%@ · Shared by %@"), notice.projectName,
                                        controller.reviewStore.hostName(for: connection)))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button(L10n.text("Open")) {
                            browsingID = notice.downloadID
                            browsingPath = notice.entry.path
                            controller.dismissNewFile(connectionID: connection.id, projectID: notice.projectID,
                                                     path: notice.entry.path)
                        }.disabled(!notice.isDownloaded && !controller.helper.online)
                        Button(L10n.text("Keep offline")) {
                            Task {
                                await controller.keepNewFileOffline(connectionID: connection.id,
                                    projectID: notice.projectID, path: notice.entry.path)
                            }
                        }.disabled(!controller.helper.online || controller.busy)
                        Button(L10n.text("Ignore"), systemImage: "xmark") {
                            controller.dismissNewFile(connectionID: connection.id, projectID: notice.projectID,
                                                      path: notice.entry.path)
                        }
                        .labelStyle(.iconOnly)
                        .help(L10n.text("Dismiss this notice. Browse files can still open it; existing offline rules still apply."))
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        }
    }

    private func acceptedProjects(_ connection: DesktopPeerConnection) -> some View {
        let projects = (controller.available[connection.id] ?? []).filter {
            controller.reviewStore.acceptsProject(connectionID: connection.id, projectID: $0.id)
        }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.text("Projects on this computer"), count: projects.count)
            if projects.isEmpty {
                Text(L10n.text("Add a shared project to keep it in this list."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(projects) { descriptor in
                    let downloadID = DesktopPeerController.downloadID(connectionID: connection.id, projectID: descriptor.id)
                    let cached = controller.downloads.projects.first { $0.id == downloadID }
                    HStack(spacing: 9) {
                        Image(systemName: "folder").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(descriptor.name).font(.headline)
                            Text(cached.map { String(format: L10n.text("%@ · %d remote files"),
                                                     controller.reviewStore.hostName(for: connection), $0.catalogue.files.count) }
                                 ?? controller.reviewStore.hostName(for: connection))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(L10n.text("Browse files")) { browsingID = downloadID }
                            .disabled(cached == nil)
                        Button(L10n.text("Create editable copy")) {
                            Task { await controller.importProject(connectionID: connection.id, projectID: descriptor.id) }
                        }.disabled(!controller.helper.online || controller.busy)
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        }
    }

    private func fileNotices(for connection: DesktopPeerConnection) -> [FileNotice] {
        (controller.available[connection.id] ?? []).flatMap { descriptor -> [FileNotice] in
            let downloadID = DesktopPeerController.downloadID(connectionID: connection.id, projectID: descriptor.id)
            guard let project = controller.downloads.projects.first(where: { $0.id == downloadID }) else { return [] }
            let paths = controller.reviewStore.pendingFilePaths(connectionID: connection.id, projectID: descriptor.id)
            return project.catalogue.files.filter { paths.contains($0.path) }.map {
                FileNotice(projectID: descriptor.id, projectName: descriptor.name, downloadID: downloadID,
                           entry: $0, isDownloaded: project.isDownloaded($0))
            }
        }
        .sorted {
            let projectOrder = $0.projectName.localizedStandardCompare($1.projectName)
            if projectOrder == .orderedSame {
                return $0.entry.path.localizedStandardCompare($1.entry.path) == .orderedAscending
            }
            return projectOrder == .orderedAscending
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.headline)
            if count > 0 { Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
    }

    private func renameSheet(_ connection: DesktopPeerConnection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Rename computer")).font(.title2.bold())
            Text(L10n.text("This name is saved on this Mac and helps identify where its projects come from."))
                .font(.callout).foregroundStyle(.secondary)
            TextField(L10n.text("Computer name"), text: $hostNameDraft)
                .accessibilityIdentifier("remote-host-name")
            HStack {
                Button(L10n.text("Cancel")) { renamingConnection = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text("Save")) {
                    controller.setConnectionName(hostNameDraft, connectionID: connection.id)
                    renamingConnection = nil
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 440)
    }

    private struct FileNotice: Identifiable {
        let projectID: UUID
        let projectName: String
        let downloadID: UUID
        let entry: RemoteFileEntry
        let isDownloaded: Bool
        var id: String { projectID.uuidString + ":" + entry.path }
    }
}
