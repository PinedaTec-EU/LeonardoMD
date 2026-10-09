import SwiftUI
import LeonardoSync

struct DesktopPeerPreferencesView: View {
    let session: AppSession
    @Bindable var controller: DesktopPeerController
    @Environment(\.dismiss) private var dismiss
    @State private var pairing = false
    @State private var reviewing: UUID?

    var body: some View {
        Form {
            Picker(L10n.text("Synchronization interval"), selection: Binding(
                get: { controller.syncIntervalMinutes }, set: { controller.updateInterval($0) })) {
                ForEach(DesktopPeerController.intervals, id: \.self) { minutes in
                    Text(minutes == 0 ? L10n.text("Manual") : String(format: L10n.text("Every %d minutes"), minutes)).tag(minutes)
                }
            }
            Button(L10n.text("Link another Mac")) { pairing = true }
            Text(L10n.text("Enable the direct service on the other Mac, then compare the codes on both devices."))
                .font(.caption).foregroundStyle(.secondary)
            Section(L10n.text("Linked Macs")) {
                ForEach(controller.connections, id: \.id) { connection in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(connection.endpoint.absoluteString).textSelection(.enabled)
                            Spacer()
                            if connection.revoked { Text(L10n.text("Revoked")) }
                            else { Button(L10n.text("Sync")) { Task { await controller.refresh(connection.id) } } }
                        }
                        if let code = connection.comparisonCode {
                            Text(code).font(.title2.monospaced()).textSelection(.enabled)
                            Text(L10n.text("Approve this code on the other Mac before importing a project."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(controller.available[connection.id] ?? [], id: \.id) { project in
                            HStack {
                                Text(project.name)
                                Spacer()
                                Button(L10n.text("Import")) { Task { await controller.importProject(connectionID: connection.id, projectID: project.id) } }
                            }
                        }
                    }
                }
            }
            Section(L10n.text("Offline copies")) {
                ForEach(controller.copies, id: \.id) { copy in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(copy.name).font(.headline)
                        Text((copy.selection.folders + copy.selection.documents).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack { copyActions(copy) }
                            VStack(alignment: .leading, spacing: 8) { copyActions(copy) }
                        }
                        if controller.submitted.contains(copy.id) {
                            Text(L10n.text("Sent for review on the other Mac. Later edits remain local."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else if controller.pendingProposals[copy.id] != nil {
                            Text(L10n.text("A saved proposal is pending. Retrying sends the original capture."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else if controller.unchanged.contains(copy.id) { Text(L10n.text("No changes")) }
                    }
                }
            }
        }.formStyle(.grouped).disabled(controller.busy)
        .task { await controller.initialize() }
        .sheet(isPresented: $pairing) { DesktopPeerPairingView(controller: controller) }
        .sheet(isPresented: Binding(get: { reviewing != nil }, set: { if !$0 { reviewing = nil } })) {
            if let id = reviewing, let comparison = controller.comparisons[id] {
                DesktopPeerComparisonView(comparison: comparison)
            }
        }
        .alert(L10n.text("Synchronization error"), isPresented: Binding(get: { controller.error != nil }, set: { if !$0 { controller.error = nil } })) {
            Button(L10n.text("OK")) { controller.error = nil }
        } message: { Text(controller.error ?? "") }
    }

    @ViewBuilder private func copyActions(_ copy: DesktopPeerCopy) -> some View {
        Group {
            Button(L10n.text("Open")) {
                Task {
                    if let url = await controller.open(copy.id) {
                        await session.openProject(url)
                        if session.projectURL == url { dismiss() }
                    }
                }
            }
            Button(L10n.text(controller.pendingProposals[copy.id] == nil ? "Send changes for review" : "Retry pending proposal")) {
                Task { await controller.send(copy.id) }
            }
            Button(L10n.text("Compare changes")) {
                Task {
                    await controller.compare(copy.id)
                    if controller.comparisons[copy.id] != nil { reviewing = copy.id }
                }
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

}

private struct DesktopPeerPairingView: View {
    @Bindable var controller: DesktopPeerController
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var name = Host.current().localizedName ?? "LeonardoMD"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Link another Mac")).font(.title2.bold())
            TextField(L10n.text("HTTPS address or pairing link"), text: $address)
                .accessibilityIdentifier("desktop-peer-address")
            TextField(L10n.text("Device name"), text: $name)
            if let error = controller.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text("Connect")) { Task { if await controller.enroll(address: address, name: name) { dismiss() } } }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.isEmpty)
            }.disabled(controller.busy)
        }.padding(24).frame(width: 520)
    }
}

private struct DesktopPeerComparisonView: View {
    let comparison: DesktopPeerComparison
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text("Compare changes")).font(.title2.bold())
                Spacer()
                Button(L10n.text("Done")) { dismiss() }
            }
            if comparison.comparison.differences.isEmpty { Text(L10n.text("No changes")) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(comparison.comparison.differences, id: \.path) { difference in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(difference.path).font(.headline)
                            if difference.hasConflict { Text(L10n.text("Conflict")).foregroundStyle(.orange) }
                            HStack(alignment: .top) {
                                version(L10n.text("Base"), difference.base)
                                version(L10n.text("This Mac"), difference.local)
                                version(L10n.text("Other Mac"), difference.remote)
                            }
                        }
                        Divider()
                    }
                }
            }
        }.padding(24).frame(width: 900, height: 620)
    }
    private func version(_ title: String, _ file: CorpusFile?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption.bold())
            if let file {
                if ["md", "markdown", "txt"].contains(URL(fileURLWithPath: file.path).pathExtension.lowercased()),
                   let text = String(data: file.content, encoding: .utf8) {
                    Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                } else { Text(ByteCountFormatter.string(fromByteCount: Int64(file.content.count), countStyle: .file)) }
            } else { Text(L10n.text("Deleted")) }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
