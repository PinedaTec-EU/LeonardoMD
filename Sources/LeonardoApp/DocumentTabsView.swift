import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentTabsView: View {
    @Bindable var documents: DocumentTabs
    @State private var tabFrames: [UUID: CGRect] = [:]
    @GestureState private var dragTargetID: UUID?

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
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { documents.acceptDrop($0) }
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
        .coordinateSpace(name: TabReordering.coordinateSpace)
        .onPreferenceChange(TabFramesPreference.self) { tabFrames = $0 }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .disabled(documents.closing)
        .padding(.horizontal, 12)
        .background(.bar)
    }

    private func moveTab(_ id: UUID, offset: Int) {
        guard let neighbor = documents.neighbor(of: id, offset: offset) else { return }
        documents.move(id, to: neighbor)
    }

    private func tabHeader(_ tab: DocumentTab) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .padding(4)
                .contentShape(Rectangle())
                .help("Arrastra para reordenar la pestaña")
                .accessibilityLabel("Reordenar pestaña \(tab.title)")
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
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: TabFramesPreference.self, value: [tab.id: geometry.frame(in: .named(TabReordering.coordinateSpace))])
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(documents.activeSession.accentColor, lineWidth: dragTargetID == tab.id ? 2 : 0)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named(TabReordering.coordinateSpace))
                .updating($dragTargetID) { value, state, _ in
                    state = TabReordering.destination(at: value.location, frames: tabFrames, excluding: tab.id)
                }
                .onEnded { value in
                    guard let target = TabReordering.destination(at: value.location, frames: tabFrames, excluding: tab.id) else { return }
                    documents.move(tab.id, to: target)
                }
        )
        .contextMenu {
            Button("Mover a la izquierda") { moveTab(tab.id, offset: -1) }
                .disabled(documents.neighbor(of: tab.id, offset: -1) == nil)
            Button("Mover a la derecha") { moveTab(tab.id, offset: 1) }
                .disabled(documents.neighbor(of: tab.id, offset: 1) == nil)
            Divider()
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
