import SwiftUI
import LeonardoCore

/// Defers presentation until this tab is active and other document dialogs have finished.
struct ExtensionRecommendationPresenter: ViewModifier {
    @Bindable var session: AppSession
    let isActiveTab: Bool

    private var eligible: Bool {
        isActiveTab && session.initialized && !session.busy && !session.stopped && !session.isClosing
            && !session.isSyncSuspended && !session.showPreferences && !session.showGit
            && session.pendingExternalURL == nil && session.errorMessage == nil
    }
    private struct ObservationKey: Hashable {
        let document: URL?
        let project: URL?
        let source: String
        let detectedSource: String?
        let eligible: Bool
        let features: MarkdownFeatures
        let detected: Set<BuiltInExtension>
        let suppressed: Set<BuiltInExtension>
        let resetRevision: Int
    }
    private var observationKey: ObservationKey {
        let state = session.extensionRecommendations
        return ObservationKey(document: session.documentURL, project: session.projectURL,
                              source: session.content, detectedSource: state.detectedSource,
                              eligible: eligible, features: session.features,
                              detected: state.detected, suppressed: state.preferences.suppressed,
                              resetRevision: state.preferences.resetRevision)
    }
    func body(content: Content) -> some View {
        content
            .task(id: observationKey) {
                guard !Task.isCancelled else { return }
                session.extensionRecommendations.prepare(for: session, eligible: eligible)
            }
            .sheet(item: Binding(
                get: { session.extensionRecommendations.prompt },
                set: { session.extensionRecommendations.prompt = $0 }
            )) { request in
                ExtensionRecommendationDialog(request: request) { activate, suppress in
                    session.extensionRecommendations.respond(to: request, activate: activate,
                                                             suppress: suppress, session: session)
                }
                .modifier(SessionAppearance(session: session))
            }
    }
}

struct ExtensionRecommendationDialog: View {
    let request: ExtensionRecommendation
    let respond: (Bool, Set<BuiltInExtension>) -> Void
    @State private var suppressed: Set<BuiltInExtension> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("Enable document extensions?"), systemImage: "puzzlepiece.extension")
                .font(.title2.bold())
            Text(L10n.text("This document uses disabled built-in extensions. Enable them to view its content correctly."))
            Text(L10n.text(request.project == nil
                ? "Activation changes your global extension preferences."
                : "Activation creates or updates this project's extension preferences."))
                .font(.callout).foregroundStyle(.secondary)
            ForEach(request.extensions) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(item.title)).font(.headline)
                    Toggle(L10n.text("Do not ask again for this extension"), isOn: Binding(
                        get: { suppressed.contains(item) },
                        set: { if $0 { suppressed.insert(item) } else { suppressed.remove(item) } }
                    )).accessibilityIdentifier("suppress-" + item.rawValue)
                }
            }
            HStack {
                Spacer()
                Button(L10n.text("Not now")) { respond(false, suppressed) }.keyboardShortcut(.cancelAction)
                Button(L10n.text("Enable extensions")) { respond(true, suppressed) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 490)
        .accessibilityIdentifier("extension-recommendation-dialog")
    }
}
