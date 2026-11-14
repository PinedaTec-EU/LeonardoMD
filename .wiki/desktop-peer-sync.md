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

An on-demand HTTP 403 triggers a fresh authenticated STATUS before classifying
the denial. Confirmed device revocation hides every download cache owned by that
connection immediately; a removed project or file selection invalidates only
the requested project's cache. If STATUS is inconclusive, retain the original
operation/status pair for support instead of guessing whether the device was
revoked. A file no longer selected by the source is reported as outside scope.

Keep async callback defaults in the public generic
`DirectEnrollmentClient.withRevocationRecheck` API as optional `nil` parameters
and resolve the normal STATUS behavior in its library body. Xcode 26.3 / Swift
6.2.4 can link incompatible context metadata for public async default-argument
closures across modules, aborting the test process with signal 6; the regression
is tracked by [#450](https://github.com/PinedaTec-EU/LeonardoMD/issues/450).
