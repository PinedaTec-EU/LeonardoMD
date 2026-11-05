import LeonardoSync
import SwiftUI

/// Display the granted protocol capability, never infer it from a device name.
@MainActor
enum SyncDeviceRole {
    static func description(_ kind: PairingClientKind) -> String {
        L10n.text(kind == .desktopPeer
            ? "LeonardoMD on Mac · changes require review"
            : "Read-only device · Little Leonardo or compatible client")
    }
}

struct SyncDeviceIdentity: View {
    let name: String
    let kind: PairingClientKind
    var body: some View {
        VStack(alignment: .leading) {
            Text(name)
            Text(SyncDeviceRole.description(kind)).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
