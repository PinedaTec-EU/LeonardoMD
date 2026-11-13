import AppKit
import SwiftUI

/// Accessory processes have no menu bar. Keep navigation and essential lifecycle
/// actions in every window, even when its document area is empty.
struct InstanceSwitcher: View {
    @Bindable var session: AppSession
    var presentation: InstancePresentation = .shared

    var body: some View {
        if presentation.allowsMultipleInstances || presentation.peers.count > 1 {
            HStack(spacing: 6) {
                Menu {
                    ForEach(presentation.peers, id: \.self) { identity in
                        Button(presentation.label(for: identity)) { presentation.activate(identity) }
                    }
                    Divider()
                    Button(L10n.text("New instance")) {
                        Task {
                            do { try await InstancePreferences.shared.launch() }
                            catch { session.report(error) }
                        }
                    }.disabled(!presentation.allowsMultipleInstances)
                    Button(L10n.text("Preferences…")) { session.showPreferences = true }
                    Button(L10n.text("Quit this instance")) { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "square.stack.3d.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.text("Instances"))
                .accessibilityLabel(L10n.text("Instances"))
                .accessibilityIdentifier("instance-switcher")
                if InstancePreferences.shared.groupingEnabled {
                    InstanceApplicationMenu().frame(width: 28, height: 24)
                }
            }
        }
    }
}
