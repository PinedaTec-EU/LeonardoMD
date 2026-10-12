import SwiftUI

struct UpdatePreferencesView: View {
    @Bindable var updates: ApplicationUpdates

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.text("Installed version")) {
                    Text(updates.configuration.version.version ?? L10n.text("Development build"))
                        .textSelection(.enabled)
                }
                LabeledContent(L10n.text("Installed channel")) {
                    Text(updates.configuration.installedChannel?.title ?? L10n.text("Development build"))
                }
            }
            Section {
                Picker(L10n.text("Update channel"), selection: Binding(
                    get: { updates.channel }, set: { updates.selectChannel($0) })) {
                    ForEach(UpdateChannel.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!updates.canChangeChannel)
                .accessibilityIdentifier("update-channel")
                Text(L10n.text(updates.channel == .beta
                    ? "Beta includes stable releases and experimental versions. You may encounter unfinished features or errors."
                    : "Receive stable releases only."))
                    .font(.caption).foregroundStyle(.secondary)
                if updates.configuration.installedChannel == .beta && updates.channel == .stable {
                    Text(L10n.text("Your beta stays installed until a newer stable version is available. Changing channel does not downgrade the app."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L10n.text("Automatically check for updates"), isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates }, set: { updates.setAutomaticChecks($0) }))
                    .disabled(!updates.isStarted)
                    .accessibilityIdentifier("update-automatic-checks")
                Text(L10n.text("Checks run periodically. You decide when to install an update."))
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent(L10n.text("Last check")) {
                    if let date = updates.lastUpdateCheckDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    } else { Text(L10n.text("Never")) }
                }
                Button(L10n.text("Check for updates now")) { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
                    .accessibilityIdentifier("update-check-now")
                if updates.sessionInProgress {
                    Text(L10n.text("Finish or cancel the current update before changing channel."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !updates.configuration.isConfigured {
                Section {
                    Text(L10n.text("Updates not configured")).font(.headline)
                    Text(L10n.text("This development build has no signed update channel. Install a distribution version to receive updates."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let error = updates.startupError {
                Section {
                    Text(L10n.text("Updates unavailable")).font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped).toggleStyle(PremiumSwitchStyle())
    }
}
