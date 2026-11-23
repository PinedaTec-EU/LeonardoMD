import AppKit
import SwiftUI

struct SyncHelperPreferencesSection: View {
    @Bindable var controller: SyncHelperController
    @State private var showsDiagnostics = false

    static var explanation: String {
        L10n.text("When off, sharing and remote access stop even with LeonardoMD open. Starts at login and shares saved files after you close the editor.")
    }

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

            Text(Self.explanation)
                .font(.caption).foregroundStyle(.secondary)

            if showsWarning {
                Text(controller.diagnostics.status)
                    .font(.caption).foregroundStyle(.secondary)
            }

            if controller.showsApprovalAction {
                Button(L10n.text("Open Login Items settings")) { controller.openApprovalSettings() }
                    .buttonStyle(PremiumButtonStyle(compact: true))
            }

            HStack {
                Spacer()
                Button(L10n.text("View diagnostics…")) { showsDiagnostics = true }
                    .buttonStyle(PremiumButtonStyle(compact: true))
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
            HStack {
                Text(L10n.text("Leonardo Sync diagnostics")).font(.headline)
                Spacer()
                Button(L10n.text("Done")) { dismiss() }
                    .buttonStyle(PremiumButtonStyle(compact: true))
                    .keyboardShortcut(.defaultAction)
            }
            DiagnosticReportText(report: report)
                .frame(height: 174)
                .background { PremiumControlBackground(selected: true) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        feedback = L10n.text("Could not open a mail draft.")
                    }
                } label: {
                    Label(L10n.text("Email diagnostics…"), systemImage: "envelope")
                }
            }
            .buttonStyle(PremiumButtonStyle(compact: true))
            .labelStyle(.titleAndIcon)
            Text(L10n.format(
                "If no draft opens, choose Copy diagnostics and paste the report into an email to %@.",
                SyncHelperDiagnostics.supportEmail
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onChange(of: report) { feedback = nil }
    }
}

/// Use AppKit selection and clipboard actions for the read-only report.
private struct DiagnosticReportText: NSViewRepresentable {
    let report: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        guard let text = scroll.documentView as? NSTextView else { return scroll }
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textColor = .labelColor
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.setAccessibilityLabel(L10n.text("Leonardo Sync diagnostics"))

        let menu = NSMenu()
        for (title, action) in [("Copy", #selector(NSTextView.copy(_:))),
                                ("Select all", #selector(NSTextView.selectAll(_:)))] {
            let item = NSMenuItem(title: L10n.text(title), action: action, keyEquivalent: "")
            item.target = text
            menu.addItem(item)
        }
        text.menu = menu
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, text.string != report else { return }
        text.string = report
    }
}
