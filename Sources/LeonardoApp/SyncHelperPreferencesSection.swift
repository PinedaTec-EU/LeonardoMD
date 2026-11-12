import SwiftUI

struct SyncHelperPreferencesSection: View {
    @Bindable var controller: SyncHelperController
    private var showsStatusIndicator: Bool {
        controller.hasPresentedStatus && (controller.enabled || controller.displayedState == .failed)
    }
    private var showsDiagnostic: Bool {
        switch controller.displayedState {
        case .notInstalled, .approvalRequired, .failed: true
        case .disabled, .starting, .running: false
        }
    }

    var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { controller.enabled },
                    set: { value in Task { await controller.setEnabled(value) } })) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(controller.displayedState == .running ? Color.green : Color.red)
                            .frame(width: 9, height: 9)
                            .opacity(showsStatusIndicator ? 1 : 0)
                            .accessibilityHidden(!showsStatusIndicator)
                            .accessibilityLabel(controller.statusText)
                        Text(L10n.text("Enable Leonardo Sync"))
                    }
                }
                    .disabled(controller.busy && (!controller.upgrading || !controller.enabled))
                Text(showsDiagnostic ? controller.statusText : " ")
                    .lineLimit(1).foregroundStyle(.secondary)
                Text(L10n.text("Required to share and connect. When off, both directions are offline even with LeonardoMD open. Starts after login and keeps sharing saved files when you close the editor."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Open Login Items settings")) { controller.openApprovalSettings() }
                    .opacity(controller.showsApprovalAction ? 1 : 0)
                    .disabled(!controller.showsApprovalAction)
                    .accessibilityHidden(!controller.showsApprovalAction)
                Text(controller.displayedError ?? " ")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topLeading)
                    .help(controller.displayedError ?? "")
                    .accessibilityHidden(controller.displayedError == nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await controller.refreshAfterActivation() }
            }
    }
}
