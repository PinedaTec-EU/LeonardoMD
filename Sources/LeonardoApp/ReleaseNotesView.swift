import SwiftUI
import LeonardoCore

struct ReleaseNotesView: View {
    @Environment(\.leonardoAccent) private var accent
    let notes: ReleaseChanges
    let baseline: String?
    var showFullHistory = false
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
                    ForEach(displayedChanges) { change in
                        changeRow(
                            pr: change.pr,
                            version: change.toVersion,
                            url: URL(string: "https://github.com/\(notes.repository)/pull/\(change.pr)")!,
                            summary: HistoricalReleaseNote.byPR[change.pr].map(localizedSummary)
                                ?? change.summary
                                ?? L10n.text("No detailed summary was recorded for this historical change.")
                        )
                    }
                    if !additionalHistory.isEmpty {
                        Text(L10n.text("Other changes through PR #207")).font(.headline)
                        ForEach(additionalHistory) { note in
                            changeRow(pr: note.pr, version: nil, url: note.url, summary: localizedSummary(note))
                        }
                    }
                    if displayedChanges.isEmpty && additionalHistory.isEmpty {
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
                    .buttonStyle(PremiumButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("release-notes-done")
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 400)
        .background(.background)
        .accessibilityIdentifier("release-notes-window")
    }

    private var displayedChanges: [ReleaseChanges.Change] {
        notes.changes(after: showFullHistory ? nil : baseline)
    }

    private var additionalHistory: [HistoricalReleaseNote] {
        guard showFullHistory else { return [] }
        let versionedPRs = Set(notes.changes.map(\.pr))
        return HistoricalReleaseNote.all.filter { !versionedPRs.contains($0.pr) }
    }

    private func localizedSummary(_ note: HistoricalReleaseNote) -> String {
        LanguageSettings.shared.language == .spanish ? note.es : note.en
    }

    private func changeRow(pr: Int, version: String?, url: URL, summary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Link(L10n.format("PR #%d", pr), destination: url).foregroundStyle(accent)
                Spacer()
                if let version {
                    Text(version).foregroundStyle(.secondary).font(.caption)
                }
            }
            Text(summary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    var coverageText: String {
        if showFullHistory { return L10n.text("Recorded release history") }
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
