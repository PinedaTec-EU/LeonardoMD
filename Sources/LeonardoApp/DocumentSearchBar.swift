import SwiftUI

struct DocumentSearchBar: View {
    @Bindable var search: DocumentSearch
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void
    @FocusState private var queryFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(L10n.text("Find in open documents"), text: $search.query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150, maxWidth: 320)
                .focused($queryFocused)
                .onSubmit(onNext)
                .accessibilityIdentifier("document-search-field")

            Toggle(isOn: $search.matchCase) { Text("Aa") }
                .toggleStyle(.button)
                .help(L10n.text("Match case"))
                .accessibilityLabel(L10n.text("Match case"))
                .accessibilityIdentifier("document-search-match-case")

            Toggle(isOn: $search.usesRegularExpression) { Text(".*") }
                .toggleStyle(.button)
                .help(L10n.text("Use regular expressions"))
                .accessibilityLabel(L10n.text("Use regular expressions"))
                .accessibilityIdentifier("document-search-regex")

            Menu {
                Button { search.scope = .currentDocument } label: {
                    Label(L10n.text("This document"),
                          systemImage: search.scope == .currentDocument ? "checkmark" : "doc.text")
                }
                Button { search.scope = .openDocuments } label: {
                    Label(L10n.text("All open documents"),
                          systemImage: search.scope == .openDocuments ? "checkmark" : "doc.on.doc")
                }
            } label: {
                HStack(spacing: 5) {
                    Text(search.scope == .currentDocument
                         ? L10n.text("This document") : L10n.text("All open documents"))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .help(L10n.text("Search scope"))
            .accessibilityLabel(L10n.text("Search scope"))
            .accessibilityValue(search.scope == .currentDocument
                                ? L10n.text("This document") : L10n.text("All open documents"))
            .accessibilityIdentifier("document-search-scope")

            Text(search.statusMessage)
                .font(.caption)
                .foregroundStyle(search.hasInvalidRegularExpression ? Color.red : Color.secondary)
                .lineLimit(1)
                .frame(minWidth: 72, maxWidth: 220, alignment: .leading)
                .accessibilityIdentifier("document-search-status")

            Button(action: onPrevious) { Image(systemName: "chevron.up") }
                .help(L10n.text("Previous match"))
                .accessibilityLabel(L10n.text("Previous match"))
                .accessibilityIdentifier("document-search-previous")
                .disabled(!search.canNavigate)

            Button(action: onNext) { Image(systemName: "chevron.down") }
                .help(L10n.text("Next match"))
                .accessibilityLabel(L10n.text("Next match"))
                .accessibilityIdentifier("document-search-next")
                .disabled(!search.canNavigate)

            Button(action: onClose) { Image(systemName: "xmark") }
                .help(L10n.text("Close search"))
                .accessibilityLabel(L10n.text("Close search"))
                .accessibilityIdentifier("document-search-close")
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { queryFocused = true }
        .onExitCommand(perform: onClose)
    }
}
