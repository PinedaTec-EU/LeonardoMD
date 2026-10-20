import SwiftUI

struct ReleaseNotesView: View {
    let notes: ReleaseChanges
    let baseline: String?
    @State var suppress: Bool = true
    let onSuppressionChange: (Bool) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("What's new in LeonardoMD")).font(.title2.bold())
                Text(L10n.format("Version %@", notes.version)).font(.headline)
                Text(coverageText).font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(notes.changes(after: baseline)) { change in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Link(L10n.format("PR #%d", change.pr), destination: URL(
                                    string: "https://github.com/\(notes.repository)/pull/\(change.pr)"
                                )!)
                                Spacer()
                                Text(change.toVersion).foregroundStyle(.secondary).font(.caption)
                            }
                            Text(change.summary ?? L10n.text("No detailed summary was recorded for this historical change."))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .contain)
                    }
                    if notes.changes(after: baseline).isEmpty {
                        Text(L10n.text("No additional changes in this version interval.")).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .accessibilityIdentifier("release-notes-changes")
            Divider()
            HStack(spacing: 24) {
                Toggle(L10n.text("Do not show again for this version"), isOn: $suppress)
                    .toggleStyle(PremiumSwitchStyle())
                    .onChange(of: suppress) { _, value in onSuppressionChange(value) }
                    .accessibilityIdentifier("release-notes-suppress")
                Button(L10n.text("Done"), action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("release-notes-done")
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 400)
        .accessibilityIdentifier("release-notes-window")
    }

    private var coverageText: String {
        if let baseline, let previous = ReleaseChanges.parts(baseline), let current = ReleaseChanges.parts(notes.version),
           current.lexicographicallyPrecedes(previous) {
            return L10n.text("An earlier version is installed. Showing its recorded history, not changes added by this downgrade.")
        }
        if let baseline, baseline == notes.initialVersion || notes.changes.contains(where: { $0.toVersion == baseline }) {
            return L10n.format("Changes since version %@", baseline)
        }
        return L10n.format("Recorded history since version %@. Earlier changes may not be available.", notes.initialVersion)
    }
}
