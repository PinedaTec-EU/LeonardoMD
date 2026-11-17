import SwiftUI
import LeonardoCore
import LeonardoRender
import LeonardoSync
import LeonardoSyncUI

@MainActor
struct MobileRemoteDocumentPreview: View {
    let library: DownloadLibrary
    let projectID: UUID
    let entry: RemoteFileEntry
    let spanish: Bool
    let appearance: MarkdownAppearance
    let compactFirstHeading: Bool
    let failureDiagnosticPresentation: RemoteDownloadDiagnosticPresentation?

    @ObservedObject private var preferences: MobileMarkdownPreferences
    @StateObject private var recommendations: MobileExtensionRecommendations
    @State private var activeDocumentPath: String?

    init(library: DownloadLibrary, projectID: UUID, entry: RemoteFileEntry, spanish: Bool,
         appearance: MarkdownAppearance = .default, compactFirstHeading: Bool = false,
         failureDiagnosticPresentation: RemoteDownloadDiagnosticPresentation? = nil) {
        self.library = library
        self.projectID = projectID
        self.entry = entry
        self.spanish = spanish
        self.appearance = appearance
        self.compactFirstHeading = compactFirstHeading
        self.failureDiagnosticPresentation = failureDiagnosticPresentation
        _preferences = ObservedObject(wrappedValue: MobileMarkdownPreferences.shared)
        _recommendations = StateObject(wrappedValue: MobileExtensionRecommendations())
    }

    var body: some View {
        RemoteDocumentPreview(
            library: library,
            projectID: projectID,
            entry: entry,
            spanish: spanish,
            appearance: appearance,
            compactFirstHeading: compactFirstHeading,
            failureDiagnosticPresentation: failureDiagnosticPresentation,
            markdownFeatures: preferences.features,
            onDetectedExtensions: handleDetectedExtensions,
            onPreviewDocumentActivated: activateDocument,
            onPreviewDocumentDeactivated: deactivateDocument,
            onPreviewDocumentContentWillReload: invalidateDocument
        )
        .sheet(item: Binding(
            get: { recommendations.prompt },
            set: { if $0 == nil { recommendations.dismissPrompt() } }
        )) { request in
            MobileExtensionRecommendationDialog(request: request, spanish: spanish) { choice, enableSelected in
                recommendations.respond(to: request, choice: choice, enableSelected: enableSelected,
                                        preferences: preferences)
            }
        }
        .onChange(of: preferences.extensionWarningResetRevision) { _, _ in
            recommendations.warningPreferencesDidReset(preferences: preferences)
        }
    }

    private func activateDocument(path: String) {
        activeDocumentPath = path
        recommendations.activate(document: MobileDocumentIdentity(projectID: projectID, path: path), preferences: preferences)
    }

    private func deactivateDocument(path: String) {
        recommendations.deactivate(document: MobileDocumentIdentity(projectID: projectID, path: path))
        if activeDocumentPath == path { activeDocumentPath = nil }
    }

    private func invalidateDocument(path: String) {
        recommendations.documentContentWillReload(MobileDocumentIdentity(projectID: projectID, path: path))
    }

    private func handleDetectedExtensions(path: String, source: String, identifiers: [String]) {
        guard activeDocumentPath == path else { return }
        recommendations.inspect(document: MobileDocumentIdentity(projectID: projectID, path: path),
                                source: source, detectedIDs: identifiers, preferences: preferences)
    }
}
