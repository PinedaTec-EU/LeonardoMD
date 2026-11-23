import SwiftUI

/// Roles are per connection: the same Mac can publish and consume content.
struct SynchronizationPreferencesView: View {
    enum Page: String, CaseIterable, Identifiable {
        case sharing, connections
        var id: Self { self }
        var artwork: PreferencesArtwork { self == .sharing ? .share : .remote }
        @MainActor var title: String { L10n.text(self == .sharing ? "Share" : "Remote") }
        @MainActor var help: String { L10n.text(self == .sharing ? "Share from this Mac" : "Connect to other computers") }
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
            GroupBox {
                SyncHelperPreferencesSection(controller: source.helper)
                    .toggleStyle(PremiumSwitchStyle())
                    .padding(8)
            }.padding(.horizontal, 16).fixedSize(horizontal: false, vertical: true)
            SyncRoleSelector(selection: $page)
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
    }
}
