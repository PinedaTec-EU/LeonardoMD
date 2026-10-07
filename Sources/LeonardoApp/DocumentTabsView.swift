import AppKit
import SwiftUI

struct DocumentTabsView: View {
    @Bindable var documents: DocumentTabs

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ZStack {
                ForEach(documents.tabs) { tab in
                    WorkspaceView(session: tab.session)
                        .opacity(tab.id == documents.activeID ? 1 : 0)
                        .allowsHitTesting(tab.id == documents.activeID && !documents.closing)
                        .disabled(tab.id != documents.activeID || documents.closing)
                        .accessibilityHidden(tab.id != documents.activeID)
                }
            }
        }
        .modifier(SessionAppearance(session: documents.activeSession))
        .dropDestination(for: URL.self) { urls, _ in
            guard !documents.closing, DocumentTabs.acceptsDrop(urls) else { return false }
            Task { await documents.openDroppedDocuments(urls) }
            return true
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(documents.tabs) { tab in tabHeader(tab) }
                }.padding(.vertical, 6)
            }.scrollIndicators(.hidden)
            Button { documents.addTab() } label: { Image(systemName: "plus").padding(6) }
                .help("Nueva pestaña (⌘T)")
                .accessibilityLabel("Nueva pestaña")
                .accessibilityIdentifier("new-document-tab")
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .disabled(documents.closing)
        .padding(.horizontal, 12)
        .background(.bar)
    }

    private func tabHeader(_ tab: DocumentTab) -> some View {
        HStack(spacing: 6) {
            Button { documents.select(tab.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: tab.session.isDirty ? "circle.fill" : "doc.text")
                    Text(tab.title).lineLimit(1)
                }.frame(minWidth: 100, maxWidth: 200, alignment: .leading)
            }
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(tab.id == documents.activeID ? .isSelected : [])
            Button { Task { await documents.close(tab.id) } } label: {
                Image(systemName: "xmark").font(.caption)
            }.accessibilityLabel("Cerrar pestaña \(tab.title)")
        }
        .padding(4)
        .background(tab.id == documents.activeID ? documents.activeSession.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .help(tab.location?.path ?? "Abre un documento o proyecto en esta pestaña")
        .contextMenu {
            Button("Mostrar en Finder") { documents.reveal(tab.id) }.disabled(tab.location == nil)
            Button("Copiar ruta") {
                guard let url = tab.location else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }.disabled(tab.location == nil)
            Divider()
            Button("Cerrar pestaña") { Task { await documents.close(tab.id) } }
        }
    }
}
