import SwiftUI

struct SyncHelperPreferencesSection: View {
    @Bindable var controller: SyncHelperController
    var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { controller.enabled },
                    set: { value in Task { await controller.setEnabled(value) } })) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(controller.checking || controller.state == .starting ? Color.gray : (controller.online ? Color.green : Color.red))
                            .frame(width: 9, height: 9)
                            .accessibilityLabel(controller.checking || controller.state == .starting
                                ? L10n.text("Checking synchronization status") : controller.statusText)
                        Text(L10n.text("Enable Leonardo Sync"))
                    }
                }
                    .disabled(controller.busy && (!controller.upgrading || !controller.enabled))
                Text(controller.statusText).foregroundStyle(.secondary)
                Text(L10n.text("Required to share and connect. When off, both directions are offline even with LeonardoMD open. Starts after login and keeps sharing saved files when you close the editor."))
                    .font(.caption).foregroundStyle(.secondary)
                if controller.state == .approvalRequired {
                    Button(L10n.text("Open Login Items settings")) { controller.openApprovalSettings() }
                }
                if let error = controller.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
    }
}
