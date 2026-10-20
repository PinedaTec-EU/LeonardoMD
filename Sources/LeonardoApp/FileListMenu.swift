import SwiftUI

/// Sidebar controls apply to every expanded directory in this session.
struct FileListMenu: View {
    @Bindable var session: AppSession

    var body: some View {
        Menu {
            Toggle(L10n.text("Show all files"), isOn: $session.showAllFiles)
            Toggle(L10n.text("Show hidden files"), isOn: $session.showHidden)
            Menu(L10n.text("Sort")) {
                Toggle(L10n.text("Folders first"), isOn: $session.foldersFirst)
                Divider()
                Picker(L10n.text("Name"), selection: $session.fileSortDescending) {
                    Text(L10n.text("A–Z")).tag(false)
                    Text(L10n.text("Z–A")).tag(true)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.text("Filter and sort files"))
        .accessibilityLabel(L10n.text("Filter and sort files"))
        .accessibilityIdentifier("file-list-filter")
    }
}

enum LeonardoFileStyle {
    static let wine = Color(red: 0.56, green: 0.16, blue: 0.26)
}
