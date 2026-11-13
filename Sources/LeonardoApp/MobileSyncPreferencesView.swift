import SwiftUI
import CoreImage.CIFilterBuiltins
import LeonardoSync
import LeonardoCore

struct MobileSyncPreferencesView: View {
    let session: AppSession
    @Bindable var controller: DesktopSyncController
    @State private var approving: PairingRequest?
    @State private var selectingContent = false
    var body: some View {
        Form {
            Text(L10n.text("Choose saved content from this Mac for Little Leonardo and other computers. Connecting to another computer does not require sharing your own files."))
                .font(.callout).foregroundStyle(.secondary)
            Toggle(L10n.text("Share saved files from this Mac"), isOn: Binding(
                get: { controller.settings.enabled }, set: { value in
                    var updated = controller.settings; updated.enabled = value
                    Task { await controller.update(updated) }
                }))
            Toggle(L10n.text("Allow private overlay VPN"), isOn: Binding(
                get: { controller.settings.privateOverlayEnabled }, set: { value in
                    var updated = controller.settings; updated.privateOverlayEnabled = value
                    Task { await controller.update(updated) }
                }))
            Text(L10n.text("Private LAN is used by default. Enable this only for a private 100.64/10 overlay such as Tailscale."))
                .font(.caption).foregroundStyle(.secondary)
            Picker(L10n.text("Local address"), selection: Binding(get: { controller.settings.host ?? "" }, set: { value in
                var updated = controller.settings; updated.host = value.isEmpty ? nil : value
                Task { await controller.update(updated) }
            })) {
                Text(L10n.text("Automatic")).tag("")
                ForEach(controller.addresses, id: \.self) { Text($0).tag($0) }
            }
            sharedContent
            invitation
            pendingConnections
            incomingChanges
            authorizedDevices
        }.formStyle(.grouped).toggleStyle(PremiumSwitchStyle()).disabled(controller.busy)
        .task {
            await controller.initialize()
            while !Task.isCancelled {
                await controller.refreshConsent(refreshHelper: false)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .sheet(item: $controller.reviewing) { value in DesktopSourceReviewView(controller: controller, value: value) }
        .sheet(item: $approving) { request in PairingConsentView(controller: controller, request: request) }
        .sheet(isPresented: $selectingContent) {
            if let root = session.projectURL { SharedProjectSelectionView(root: root, controller: controller) }
        }
        .alert(L10n.text("Synchronization error"), isPresented: Binding(get: { controller.error != nil }, set: { if !$0 { controller.error = nil } })) {
            Button(L10n.text("OK")) { controller.error = nil }
        } message: { Text(controller.error ?? "") }
    }

    @ViewBuilder private var sharedContent: some View {
        Section(L10n.text("Content shared from this Mac")) {
            if session.projectURL != nil {
                Button(L10n.text("Share current project")) { selectingContent = true }
            }
            ForEach(controller.settings.projects) { project in
                SharedProjectRow(project: project, controller: controller)
            }
    }
    if controller.settings.projects.isEmpty {
        Text(L10n.text("Open a project and choose Share current project to select its folders or files."))
            .font(.caption).foregroundStyle(.secondary)
    }
    }

    private var invitation: some View {
        DesktopPairingInvitationSection(controller: controller)
    }

    @ViewBuilder private var pendingConnections: some View {
        Section(L10n.text("Pending connections")) {
            ForEach(controller.consent.requests) { request in
                HStack {
                    SyncDeviceIdentity(name: request.deviceName, kind: request.kind)
                    Text(request.comparisonCode).monospaced()
                    Spacer()
                    Button(L10n.text("Review")) { approving = request }
                        .disabled(!controller.consentActionsAvailable)
                    Button(L10n.text("Reject")) { Task { await controller.reject(request.id) } }
                        .disabled(!controller.consentActionsAvailable)
                }
            }
    }
    }

    @ViewBuilder private var incomingChanges: some View {
        Section(L10n.text("Incoming changes")) {
            if controller.incoming.isEmpty { Text(L10n.text("No proposals awaiting review")).foregroundStyle(.secondary) }
            ForEach(controller.incoming) { item in
                IncomingProposalRow(item: item, controller: controller)
            }
    }
    }

    @ViewBuilder private var authorizedDevices: some View {
        Section {
            ForEach(controller.consent.devices) { device in
                AuthorizedDeviceRow(device: device, controller: controller)
            }
        } header: {
            HStack {
                Text(L10n.text("Devices with access to this Mac"))
                Spacer()
                Button(L10n.text("Refresh linked devices"), systemImage: "arrow.clockwise") {
                    Task { await controller.refreshConsent() }
                }
                .buttonStyle(.borderless)
                .disabled(controller.busy)
            }
        }
    }


}

struct DesktopPairingInvitationSection: View {
    @Bindable var controller: DesktopSyncController

    var body: some View {
        if let running = controller.running {
            Text(L10n.text("Invite a device")).font(.headline)
            Text(L10n.text("Open the invitation link on another Mac, or scan its QR in Little Leonardo. Compare the codes and approve access here."))
                .font(.caption).foregroundStyle(.secondary)
            Text(running.endpoint.absoluteString).textSelection(.enabled)
            Button(L10n.text("Create pairing QR")) { Task { await controller.createQR() } }
                .disabled(!controller.pairingInvitationAvailable)
            if let url = controller.invitationURL, let image = qrImage(url.absoluteString) {
                Button(L10n.text("Copy pairing link")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 170, height: 170)
                    .accessibilityLabel(L10n.text("Device invitation QR"))
            }
        }
    }

    private func qrImage(_ value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

struct IncomingProposalRow: View {
    let item: DesktopPeerIncomingProposal
    @Bindable var controller: DesktopSyncController

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.deviceName)
                Text(controller.settings.projects.first(where: { $0.id == item.upload.projectID })?.name ?? item.upload.projectID.uuidString)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.text("Review changes")) { Task { await controller.reviewProposal(item) } }
                .disabled(!controller.sharingAvailable)
        }
    }
}

struct AuthorizedDeviceRow: View {
    let device: PairedDevice
    @Bindable var controller: DesktopSyncController

    var body: some View {
        HStack {
            SyncDeviceIdentity(name: device.name, kind: device.kind)
            Spacer()
            if device.revoked { Text(L10n.text("Revoked")).foregroundStyle(.secondary) }
            else {
                Button(L10n.text("Revoke")) { Task { await controller.revoke(device.id) } }
                    .disabled(!controller.consentActionsAvailable)
            }
        }
    }
}

struct PairingConsentView: View {
    let controller: DesktopSyncController
    let request: PairingRequest
    @Environment(\.dismiss) private var dismiss
    @State private var projects: Set<UUID> = []
    @State private var confirmed = false
    private var captureOnly: Bool {
        request.kind == .readOnly && request.capabilities.contains(.rubricExchangeV1)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.deviceName).font(.title2)
            Text(SyncDeviceRole.description(request.kind))
                .font(.caption).foregroundStyle(.secondary)
            if captureOnly {
                Text(L10n.text("This Little Leonardo can create rubrics requested by this Mac without access to any project. Select projects only if you also want offline reading."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(request.comparisonCode).font(.largeTitle.monospaced())
            Toggle(L10n.text("The codes match on both devices"), isOn: $confirmed)
            ForEach(controller.settings.projects) { project in
                Toggle(project.name, isOn: Binding(get: { projects.contains(project.id) }, set: {
                    if $0 { projects.insert(project.id) } else { projects.remove(project.id) }
                }))
            }
            PairingConsentActions(controller: controller, projects: projects,
                captureOnly: captureOnly, confirmed: confirmed, onCancel: { dismiss() }, onAllow: {
                    Task {
                        if await controller.approve(request, projects: projects) == .completed { dismiss() }
                    }
                })
        }.padding(24).frame(width: 420).buttonStyle(PremiumButtonStyle()).toggleStyle(PremiumSwitchStyle())
    }
}

struct PairingConsentActions: View {
    let controller: DesktopSyncController
    let projects: Set<UUID>
    let captureOnly: Bool
    let confirmed: Bool
    let onCancel: () -> Void
    let onAllow: () -> Void

    var body: some View {
        HStack {
            Button(L10n.text("Cancel"), action: onCancel)
            Spacer()
            Button(L10n.text("Allow connection"), action: onAllow)
                .disabled(!confirmed || (!captureOnly && projects.isEmpty) || controller.busy || !controller.consentActionsAvailable)
        }
    }
}

/// Shared by Preferences and native transition evidence.
struct SharedProjectRow: View {
    let project: MobileSharedProject
    @Bindable var controller: DesktopSyncController

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                ProjectIdentityLabel(name: project.name, identity: .sharedFromThisDevice,
                                     detail: DesktopProjectPresentation.scopeDescription(folders: project.folders))
                if !controller.sharingPresentationAvailable {
                    Text(L10n.text("Sharing paused or unavailable")).font(.caption).foregroundStyle(.secondary)
                }
                Text((project.folders.map { $0.isEmpty ? L10n.text("Entire project") : $0 } + project.documents).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.text("Remove")) { Task { await controller.unshare(project.id) } }
        }
    }
}
