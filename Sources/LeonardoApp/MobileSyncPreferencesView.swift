import SwiftUI
import CoreImage.CIFilterBuiltins
import LeonardoSync

struct MobileSyncPreferencesView: View {
    let session: AppSession
    @Bindable var controller: DesktopSyncController
    @State private var approving: PairingRequest?
    @State private var selectingContent = false
    var body: some View {
        Form {
            Toggle(L10n.text("Enable Little Leonardo service"), isOn: Binding(
                get: { controller.settings.enabled }, set: { value in
                    var updated = controller.settings; updated.enabled = value
                    Task { await controller.update(updated) }
                }))
            Picker(L10n.text("Local address"), selection: Binding(get: { controller.settings.host ?? "" }, set: { value in
                var updated = controller.settings; updated.host = value.isEmpty ? nil : value
                Task { await controller.update(updated) }
            })) {
                Text(L10n.text("Automatic")).tag("")
                ForEach(controller.addresses, id: \.self) { Text($0).tag($0) }
            }
            Section(L10n.text("Shared projects")) {
                if session.projectURL != nil {
                    Button(L10n.text("Share current project")) { selectingContent = true }
                }
                ForEach(controller.settings.projects) { project in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(project.name)
                            Text((project.folders.map { $0.isEmpty ? L10n.text("Entire project") : $0 } + project.documents).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.text("Remove")) { Task { await controller.unshare(project.id) } }
                    }
                }
            }
            if let running = controller.running {
                Text(running.endpoint.absoluteString).textSelection(.enabled)
                Button(L10n.text("Create pairing QR")) { Task { await controller.createQR() } }
                if let url = controller.invitationURL, let image = qrImage(url.absoluteString) {
                    Image(nsImage: image).interpolation(.none).resizable().frame(width: 170, height: 170)
                        .accessibilityLabel(L10n.text("Little Leonardo pairing QR"))
                }
            }
            Section(L10n.text("Pending connections")) {
                ForEach(controller.consent.requests) { request in
                    HStack {
                        Text(request.deviceName); Text(request.comparisonCode).monospaced()
                        Spacer()
                        Button(L10n.text("Review")) { approving = request }
                        Button(L10n.text("Reject")) { Task { await controller.reject(request.id) } }
                    }
                }
            }
            Section(L10n.text("Linked devices")) {
                ForEach(controller.consent.devices) { device in
                    HStack {
                        Text(device.name); Spacer()
                        if device.revoked { Text(L10n.text("Revoked")).foregroundStyle(.secondary) }
                        else { Button(L10n.text("Revoke")) { Task { await controller.revoke(device.id) } } }
                    }
                }
            }
        }.formStyle(.grouped).toggleStyle(PremiumSwitchStyle()).disabled(controller.busy)
        .task {
            await controller.initialize()
            while !Task.isCancelled {
                await controller.refreshConsent()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .sheet(item: $approving) { request in PairingConsentView(controller: controller, request: request) }
        .sheet(isPresented: $selectingContent) {
            if let root = session.projectURL { SharedProjectSelectionView(root: root, controller: controller) }
        }
        .alert(L10n.text("Synchronization error"), isPresented: Binding(get: { controller.error != nil }, set: { if !$0 { controller.error = nil } })) {
            Button(L10n.text("OK")) { controller.error = nil }
        } message: { Text(controller.error ?? "") }
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

private struct PairingConsentView: View {
    let controller: DesktopSyncController
    let request: PairingRequest
    @Environment(\.dismiss) private var dismiss
    @State private var projects: Set<UUID> = []
    @State private var confirmed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.deviceName).font(.title2)
            Text(request.comparisonCode).font(.largeTitle.monospaced())
            Toggle(L10n.text("The code matches Little Leonardo"), isOn: $confirmed)
            ForEach(controller.settings.projects) { project in
                Toggle(project.name, isOn: Binding(get: { projects.contains(project.id) }, set: {
                    if $0 { projects.insert(project.id) } else { projects.remove(project.id) }
                }))
            }
            HStack {
                Button(L10n.text("Cancel")) { dismiss() }
                Spacer()
                Button(L10n.text("Allow connection")) {
                    Task { await controller.approve(request, projects: projects); if controller.error == nil { dismiss() } }
                }.disabled(!confirmed || projects.isEmpty || controller.busy)
            }
        }.padding(24).frame(width: 420).buttonStyle(PremiumButtonStyle()).toggleStyle(PremiumSwitchStyle())
    }
}
