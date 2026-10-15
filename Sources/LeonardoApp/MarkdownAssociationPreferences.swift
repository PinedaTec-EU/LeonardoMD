import SwiftUI

struct MarkdownAssociationPreferences: View {
    @Bindable var associations: MarkdownAssociations
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section(L10n.text("Default Markdown application")) {
            Text(L10n.text(statusText)).accessibilityIdentifier("markdown-default-status")
            Text(L10n.text("Applies to .md and .markdown on this Mac, including all projects. Files with an individual Open With override may keep it."))
                .font(.caption).foregroundStyle(.secondary)
            Button(L10n.text(associations.isChanging ? "Waiting for macOS…" : "Use LeonardoMD")) {
                Task { await associations.makeDefault() }
            }
            .disabled(associations.status == .unavailable || associations.status == .leonardo
                      || associations.isChanging || associations.isPromptVisible)
            .accessibilityIdentifier("markdown-make-default")
            Toggle(L10n.text("Ask at startup when LeonardoMD is not the default"), isOn: $associations.askAtStartup)
                .accessibilityIdentifier("markdown-default-ask")
            if associations.changeFailed {
                Text(L10n.text("The change was cancelled or could not be completed. Check General preferences to see the current association and try again."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { associations.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { associations.refresh() }
        }
    }

    private var statusText: String {
        switch associations.status {
        case .unavailable: "Install a distribution version to change file associations."
        case .unknown: "Could not determine the current Markdown application."
        case .otherApplication: "LeonardoMD is not the default for all Markdown files."
        case .leonardo: "LeonardoMD is the default Markdown application."
        }
    }
}
