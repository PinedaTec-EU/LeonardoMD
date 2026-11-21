import AppKit
import SwiftUI

struct SyncHelperPreferencesSection: View {
    @Bindable var controller: SyncHelperController
    @State private var showsDiagnostics = false

    private var showsStatusIndicator: Bool {
        let state = controller.displayedState
        return controller.hasPresentedStatus && (state == .running || state == .notInstalled || state == .failed)
    }

    private var showsWarning: Bool {
        guard controller.hasPresentedStatus else { return false }
        switch controller.displayedState {
        case .notInstalled, .approvalRequired, .failed: return true
        case .disabled, .starting, .running: return controller.displayedError != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { controller.enabled },
                set: { value in Task { await controller.setEnabled(value) } }
            )) {
                HStack(spacing: 6) {
                    if showsStatusIndicator {
                        Circle()
                            .fill(controller.displayedState == .running ? Color.green : Color.red)
                            .frame(width: 9, height: 9)
                            .accessibilityLabel(controller.statusText)
                    }
                    Text(L10n.text("Enable Leonardo Sync"))
                }
            }
            .disabled(controller.busy && (!controller.upgrading || !controller.enabled))

            Text(L10n.text("Required to share and connect. When off, both directions are offline even with LeonardoMD open. Starts after login and keeps sharing saved files when you close the editor."))
                .font(.caption).foregroundStyle(.secondary)

            if showsWarning {
                Text(controller.diagnostics.status)
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if controller.showsApprovalAction {
                    Button(L10n.text("Open Login Items settings")) { controller.openApprovalSettings() }
                }
                Spacer()
                Button(L10n.text("View diagnostics…")) { showsDiagnostics = true }
            }
        }
        .sheet(isPresented: $showsDiagnostics) {
            SyncHelperDiagnosticSheet(controller: controller)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refreshAfterActivation() }
        }
    }
}

private struct SyncHelperDiagnosticSheet: View {
    let controller: SyncHelperController
    @Environment(\.dismiss) private var dismiss
    @State private var feedback: String?

    var body: some View {
        let report = controller.diagnostics.report
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Leonardo Sync diagnostics")).font(.headline)
            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    let copied = NSPasteboard.general.setString(report, forType: .string)
                    feedback = L10n.text(copied ? "Diagnostics copied" : "Could not copy diagnostics")
                } label: {
                    Label(L10n.text("Copy diagnostics"), systemImage: "doc.on.doc")
                }
                Button {
                    if let draft = SyncHelperDiagnostics.supportEmailURL(
                        subject: L10n.text("Leonardo Sync diagnostics"), report: report
                    ), NSWorkspace.shared.open(draft) {
                        feedback = nil
                    } else {
                        feedback = L10n.text("Could not open a mail draft. Copy the diagnostics to send them manually.")
                    }
                } label: {
                    Label(L10n.text("Email diagnostics…"), systemImage: "envelope")
                }
                Spacer()
                Button(L10n.text("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .labelStyle(.titleAndIcon)
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: report) { feedback = nil }
    }
}
