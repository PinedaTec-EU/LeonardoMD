import SwiftUI

struct SyncHelperPreferencesSection: View {
    @Bindable var controller: SyncHelperController
    var body: some View {
            Section("Leonardo Sync") {
                Toggle(L10n.text("Enable Leonardo Sync helper"), isOn: Binding(
                    get: { controller.enabled },
                    set: { value in Task { await controller.setEnabled(value) } }))
                    .disabled(controller.busy)
                Text(controller.statusText).foregroundStyle(.secondary)
                Text(L10n.text("Required for synchronization in both directions, even while LeonardoMD is open. Starts after login and keeps sharing saved files when you close the editor."))
                    .font(.caption).foregroundStyle(.secondary)
                if controller.state == .approvalRequired {
                    Button(L10n.text("Open Login Items settings")) { controller.openApprovalSettings() }
                }
                if let error = controller.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
    }
}
