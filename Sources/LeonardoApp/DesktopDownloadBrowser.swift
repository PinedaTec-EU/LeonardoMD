import SwiftUI
import LeonardoSync
import LeonardoSyncUI

struct DesktopDownloadBrowser: View {
    @Bindable var library: DownloadLibrary
    let projectID: UUID
    @State private var selected: RemoteFileEntry?
    @Environment(\.dismiss) private var dismiss
    private var spanish: Bool { LanguageSettings.shared.language == .spanish }
    var body: some View {
        NavigationStack {
            SyncCatalogueView(library: library, projectID: projectID, spanish: spanish) { selected = $0 }
                .padding()
                .navigationDestination(item: $selected) { entry in
                    RemoteDocumentPreview(library: library, projectID: projectID, entry: entry, spanish: spanish)
                }
                .toolbar { Button(L10n.text("Done")) { dismiss() } }
        }.frame(minWidth: 720, minHeight: 520)
    }
}
