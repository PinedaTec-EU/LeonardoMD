import LeonardoSync

/// Display the granted protocol capability, never infer it from a device name.
@MainActor
enum SyncDeviceRole {
    static func description(_ kind: PairingClientKind) -> String {
        L10n.text(kind == .desktopPeer
            ? "LeonardoMD on Mac · changes require review"
            : "Read-only device · Little Leonardo or compatible client")
    }
}
