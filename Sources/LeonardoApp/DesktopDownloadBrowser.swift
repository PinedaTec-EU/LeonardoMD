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
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let project = library.projects.first(where: { $0.id == projectID }) {
                    ProjectIdentityLabel(name: project.descriptor.name, identity: .received)
                        .padding(.horizontal)
                        .padding(.top)
                }
                SyncCatalogueView(library: library, projectID: projectID, spanish: spanish,
                                  showNonDocumentFiles: showNonDocumentFiles) { selected = $0 }
                    .padding()
            }
                .navigationDestination(item: $selected) { entry in
                    RemoteDocumentPreview(library: library, projectID: projectID, entry: entry, spanish: spanish)
                }
                .toolbar { Button(L10n.text("Done")) { dismiss() } }
        }.frame(minWidth: 720, minHeight: 520)
    }
}
