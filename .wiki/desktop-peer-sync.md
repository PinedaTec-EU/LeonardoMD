# Desktop peer synchronization

`DesktopPeerLibrary` refreshes device authorization before reading or changing a
linked project. A source Mac revoking the **device** durably revokes the local
connection, purges its managed copies/outbox and removes its stored credential;
the recipient must pair again and obtain owner approval. A removed **project
grant** leaves the device paired, purges only denied project copies and asks the
owner to restore that project's access before refreshing the list. Preserve the
difference as `SyncError.revoked` versus
`DesktopPeerLibraryError.unauthorizedProject` so the UI gives the correct
recovery action. See [#368](https://github.com/PinedaTec-EU/LeonardoMD/issues/368),
[`DesktopPeerLibrary.swift`](../Sources/LeonardoDesktopSync/DesktopPeerLibrary.swift),
and [`PeerSyncErrorMessage.swift`](../Sources/LeonardoApp/PeerSyncErrorMessage.swift).
