import SwiftUI
import LeonardoSync
import LeonardoSyncUI

struct DesktopDownloadBrowser: View {
    @Bindable var library: DownloadLibrary
    let projectID: UUID
    let showNonDocumentFiles: Bool
    @State private var selected: RemoteFileEntry?
    @Environment(\.dismiss) private var dismiss
    private var spanish: Bool { LanguageSettings.shared.language == .spanish }

    init(library: DownloadLibrary, projectID: UUID, initialPath: String? = nil, showNonDocumentFiles: Bool) {
        self.library = library
        self.projectID = projectID
        self.showNonDocumentFiles = showNonDocumentFiles
        _selected = State(initialValue: initialPath.flatMap { path in
            library.projects.first(where: { $0.id == projectID })?.catalogue.files.first(where: { $0.path == path })
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            NavigationStack {
                SyncCatalogueView(library: library, projectID: projectID, spanish: spanish,
                                  showNonDocumentFiles: showNonDocumentFiles, showsTable: true) { selected = $0 }
                    .navigationDestination(item: $selected) { entry in
                        RemoteDocumentPreview(library: library, projectID: projectID, entry: entry, spanish: spanish)
                    }
            }
        }
        .padding(24)
        .frame(width: selected == nil ? 530 : 720, height: selected == nil ? 330 : 520)
    }

    private var header: some View {
        HStack {
            if let project = library.projects.first(where: { $0.id == projectID }) {
                ProjectIdentityLabel(name: project.descriptor.name, identity: .received)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button(L10n.text("Done")) { dismiss() }
                .buttonStyle(PremiumButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
    }
}
