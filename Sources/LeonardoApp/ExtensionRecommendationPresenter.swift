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
        let legacySuppressed: Set<BuiltInExtension>
        let suppressAllWarnings: Bool
        let resetRevision: Int
    }
    private var observationKey: ObservationKey {
        let state = session.extensionRecommendations
        return ObservationKey(document: session.documentURL, project: session.projectURL,
                              source: session.content, detectedSource: state.detectedSource,
                              eligible: eligible, features: session.features,
                              detected: state.detected,
                              legacySuppressed: state.preferences.legacySuppressed,
                              suppressAllWarnings: state.preferences.suppressAllWarnings,
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
                ExtensionRecommendationDialog(request: request) { choice, action in
                    session.extensionRecommendations.respond(to: request, choice: choice,
                                                              action: action, session: session)
                }
                .modifier(SessionAppearance(session: session))
            }
    }
}

struct ExtensionRecommendationDialog: View {
    let request: ExtensionRecommendation
    let respond: (ExtensionRecommendationChoice, ExtensionRecommendationAction) -> Void
    @State private var choice: ExtensionRecommendationChoice

    init(request: ExtensionRecommendation,
         initialChoice: ExtensionRecommendationChoice = .init(),
         respond: @escaping (ExtensionRecommendationChoice, ExtensionRecommendationAction) -> Void) {
        self.request = request
        self.respond = respond
        _choice = State(initialValue: initialChoice)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("Enable document extensions?"), systemImage: "puzzlepiece.extension")
                .font(.title2.bold())
            Text(L10n.text("This document uses disabled built-in extensions. Enable them to view its content correctly."))
            Text(L10n.text(request.project == nil
                ? "Activation scope: global preferences"
                : "Activation scope: this project"))
                .font(.callout).foregroundStyle(.secondary)
            ForEach(request.extensions) { item in
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text(item.title)).font(.headline)
                        Text(L10n.text(item.purpose)).font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle(isOn: selectionBinding(for: item)) { EmptyView() }
                        .labelsHidden()
                        .toggleStyle(PremiumSwitchStyle())
                        .accessibilityLabel(Text(L10n.text(item.title)))
                        .accessibilityValue(Text(L10n.text(choice.enabledExtensions.contains(item) ? "Selected" : "Not selected")))
                        .accessibilityHint(Text(L10n.text("Select this extension to enable it")))
                        .accessibilityIdentifier("enable-" + item.rawValue)
                }
                .padding(.vertical, 3)
            }
            Divider()
            Toggle(L10n.text("Do not show this warning again"), isOn: Binding(
                get: { choice.suppressWarnings },
                set: { choice.suppressWarnings = $0 }
            ))
            .toggleStyle(PremiumSwitchStyle())
            .accessibilityIdentifier("suppress-extension-warnings")
            HStack {
                Spacer()
                Button(L10n.text("Not now")) { respond(choice, .notNow) }.keyboardShortcut(.cancelAction)
                Button(L10n.text("Enable selected")) { respond(choice, .enableSelected) }
                    .disabled(choice.enabledExtensions.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("enable-selected-extensions")
            }
        }
        .padding(24).frame(width: 490)
        .accessibilityIdentifier("extension-recommendation-dialog")
    }

    private func selectionBinding(for item: BuiltInExtension) -> Binding<Bool> {
        Binding(
            get: { choice.enabledExtensions.contains(item) },
            set: { isEnabled in
                if isEnabled {
                    choice.enabledExtensions.insert(item)
                } else {
                    choice.enabledExtensions.remove(item)
                }
            }
        )
    }
}
