import SwiftUI

struct SyncHelperPreferencesSection: View {
    @Bindable var controller: SyncHelperController
    static func statusSubtitle(isRunning: Bool, isInitialCheck: Bool,
                               status: String, checking: String) -> String {
        if isRunning { return " " }
        return isInitialCheck ? checking : status
    }

    var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { controller.enabled },
                    set: { value in Task { await controller.setEnabled(value) } })) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(controller.online ? Color.green : Color.red)
                            .frame(width: 9, height: 9)
                            .accessibilityLabel(controller.statusText)
                        Text(L10n.text("Enable Leonardo Sync"))
                    }
                }
                    .disabled(controller.busy && (!controller.upgrading || !controller.enabled))
                Text(Self.statusSubtitle(isRunning: controller.state == .running,
                                         isInitialCheck: controller.showsInitialStatusCheck,
                                         status: controller.statusText,
                                         checking: L10n.text("Checking synchronization status")))
                    .lineLimit(1).foregroundStyle(.secondary)
                    .frame(height: 18, alignment: .leading)
                Text(L10n.text("Required to share and connect. When off, both directions are offline even with LeonardoMD open. Starts after login and keeps sharing saved files when you close the editor."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Open Login Items settings")) { controller.openApprovalSettings() }
                    .opacity(controller.state == .approvalRequired ? 1 : 0)
                    .disabled(controller.state != .approvalRequired)
                    .accessibilityHidden(controller.state != .approvalRequired)
                Text(controller.error ?? " ")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topLeading)
                    .help(controller.error ?? "")
                    .accessibilityHidden(controller.error == nil)
            }
    }
}
