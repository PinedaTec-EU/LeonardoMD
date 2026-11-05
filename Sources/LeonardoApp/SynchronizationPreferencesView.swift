import SwiftUI

/// Roles are per connection: the same Mac can publish and consume content.
struct SynchronizationPreferencesView: View {
    enum Page: String, CaseIterable, Identifiable {
        case sharing, connections
        var id: Self { self }
        @MainActor var title: String { L10n.text(self == .sharing ? "Share from this Mac" : "Connect to other computers") }
    }

    let session: AppSession
    let source: DesktopSyncController
    let client: DesktopPeerController
    @State private var page: Page

    init(session: AppSession, source: DesktopSyncController = .shared,
         client: DesktopPeerController = .shared, initialPage: Page = .sharing) {
        self.session = session; self.source = source; self.client = client
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Leonardo Sync") {
                SyncHelperPreferencesSection(controller: source.helper)
                    .toggleStyle(PremiumSwitchStyle())
                    .padding(8)
            }.padding(.horizontal, 16).fixedSize(horizontal: false, vertical: true)
            Picker(L10n.text("Synchronization role"), selection: $page) {
                ForEach(Page.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16)
                .accessibilityIdentifier("synchronization-role")
                .fixedSize(horizontal: false, vertical: true)
            switch page {
            case .sharing:
                MobileSyncPreferencesView(session: session, controller: source)
                    .frame(minHeight: 0, maxHeight: .infinity)
            case .connections:
                DesktopPeerPreferencesView(session: session, controller: client)
                    .frame(minHeight: 0, maxHeight: .infinity)
            }
        }.padding(.top, 4)
        .task {
            while !Task.isCancelled {
                await source.helper.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}
