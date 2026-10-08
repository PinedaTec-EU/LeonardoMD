import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentTabsView: View {
    @Bindable var documents: DocumentTabs
    @State private var tabFrames: [UUID: CGRect] = [:]
    @GestureState private var tabDrag: TabDragState?

    private var dragTargetID: UUID? {
        guard let drag = tabDrag else { return nil }
        return TabReordering.destination(at: drag.location, frames: tabFrames, excluding: drag.sourceID)
    }

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
                }
                .padding(.vertical, 6)
                .animation(.easeInOut(duration: 0.16), value: documents.tabs.map(\.id))
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            Button { documents.addTab() } label: { Image(systemName: "plus").padding(6) }
                .help(L10n.text("New tab (⌘T)"))
                .accessibilityLabel(L10n.text("New tab"))
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

    private func reorderGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(TabReordering.coordinateSpace))
            .updating($tabDrag) { value, state, _ in
                state = TabDragState(sourceID: id, translation: value.translation, location: value.location)
            }
            .onEnded { value in
                guard let target = TabReordering.destination(at: value.location, frames: tabFrames, excluding: id) else { return }
                documents.move(id, to: target)
            }
    }

    private func tabHeader(_ tab: DocumentTab) -> some View {
        HStack(spacing: 6) {
            if tab.location != nil {
                DocumentTabGrip()
                    .padding(4)
                    .contentShape(Rectangle())
                    .help(L10n.text("Drag to reorder tab"))
                    .accessibilityLabel(L10n.format("Reorder tab %@", tab.title))
            }
            Button { documents.select(tab.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: tab.session.isDirty ? "circle.fill" : "doc.text")
                    Text(tab.title).lineLimit(1)
                }.frame(minWidth: 100, maxWidth: 200, alignment: .leading)
            }
            .help(tab.location?.path ?? L10n.text("Open a document or project in this tab"))
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(tab.id == documents.activeID ? .isSelected : [])
            Button { Task { await documents.close(tab.id) } } label: {
                Image(systemName: "xmark").font(.caption)
            }.accessibilityLabel(L10n.format("Close tab %@", tab.title))
        }
        .padding(4)
        .background(tab.id == documents.activeID ? documents.activeSession.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
        .offset(tabDrag.flatMap { $0.sourceID == tab.id ? $0.translation : nil } ?? .zero)
        .zIndex(tabDrag?.sourceID == tab.id ? 1 : 0)
        .shadow(radius: tabDrag?.sourceID == tab.id ? 6 : 0)
        .highPriorityGesture(reorderGesture(for: tab.id))
        .contextMenu {
            Button(L10n.text("Move left")) { moveTab(tab.id, offset: -1) }
                .disabled(documents.neighbor(of: tab.id, offset: -1) == nil)
            Button(L10n.text("Move right")) { moveTab(tab.id, offset: 1) }
                .disabled(documents.neighbor(of: tab.id, offset: 1) == nil)
            Divider()
            Button(L10n.text("Show in Finder")) { documents.reveal(tab.id) }.disabled(tab.location == nil)
            Button(L10n.text("Copy path")) {
                guard let url = tab.location else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }.disabled(tab.location == nil)
            Divider()
            Button(L10n.text("Close tab")) { Task { await documents.close(tab.id) } }
        }
    }
}
