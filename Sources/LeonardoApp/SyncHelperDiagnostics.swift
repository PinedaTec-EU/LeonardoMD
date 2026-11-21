import Foundation

/// Builds the report exclusively from predefined states and public app metadata.
struct SyncHelperDiagnostics {
    struct Event: Equatable {
        let date: Date
        let state: SyncHelperController.State
        let hasError: Bool

        @MainActor var label: String {
            if hasError && state == .running { return L10n.text("Sync helper reported a warning") }
            return state.diagnosticLabel
        }
    }

    private(set) var events: [Event] = []
    var lastCheck: Date?

    mutating func record(state: SyncHelperController.State, hasError: Bool, at date: Date) {
        guard events.last?.state != state || events.last?.hasError != hasError else { return }
        events.append(Event(date: date, state: state, hasError: hasError))
        if events.count > 20 { events.removeFirst() }
    }

    @MainActor var status: String {
        events.last?.label ?? L10n.text("Sync status has not been checked")
    }

    static func supportEmailURL(subject: String, report: String) -> URL? {
        var draft = URLComponents()
        draft.scheme = "mailto"
        draft.path = "leonardo@pinedatec.eu"
        draft.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: report.replacingOccurrences(of: "\n", with: "\r\n"))
        ]
        // Mail clients may interpret a literal plus sign as a space.
        draft.percentEncodedQuery = draft.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return draft.url
    }

    @MainActor var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        let checked = lastCheck?.formatted(date: .abbreviated, time: .standard) ?? L10n.text("Not yet checked")
        let history = events.reversed().map {
            "\($0.date.formatted(date: .abbreviated, time: .standard)) · \($0.label)"
        }
        return [
            L10n.text("Leonardo Sync diagnostics"),
            "LeonardoMD \(version) (\(build))",
            "\(L10n.text("Sync status")) · \(status)",
            "\(L10n.text("Last Sync check")) · \(checked)",
            "",
            L10n.text("Recent Sync events in this session")
        ].joined(separator: "\n") + "\n" + (history.isEmpty ? L10n.text("No Sync events yet") : history.joined(separator: "\n"))
    }
}

extension SyncHelperController.State {
    @MainActor var diagnosticLabel: String {
        switch self {
        case .notInstalled: L10n.text("Sync helper is not installed")
        case .disabled: L10n.text("Offline · sync helper disabled")
        case .approvalRequired: L10n.text("Offline · approve the sync helper in System Settings")
        case .starting: L10n.text("Offline · sync helper starting")
        case .running: L10n.text("Sync helper running")
        case .failed: L10n.text("Offline · sync helper unavailable")
        }
    }
}
