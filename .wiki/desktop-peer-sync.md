# Desktop peer synchronization

`DesktopPeerLibrary` refreshes device authorization before reading or changing a
linked project. A source Mac revoking the **device** durably revokes the local
connection, purges its managed copies/outbox and removes its stored credential;
the recipient must pair again and obtain owner approval. A pending, removed or
narrowed **project grant** leaves the device paired. Its durable project barrier
hides editable copies and blocks open/compare/send until authenticated
reconciliation, while preserving the working directory and any open local
editor. A stale outbound proposal is dropped so it cannot replay after retry.
The same project and selection becoming authorized makes the retained copy
available again; a narrower selection keeps the broader copy blocked. Preserve
the difference as `SyncError.revoked` versus
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

PR #369 treats missing local credentials as a durable revoked-state witness if
the connection snapshot cannot be saved after a confirmed revocation. It removes
the credential before writing the revoked snapshot and keeps an in-process denial
barrier, so a later library load cannot reopen the old grant from stale metadata.
Project grant transitions write a separate durable authorization barrier before
the fallible connection snapshot save. The desktop library checks that barrier
before exposing or opening editable copies, including after restart. Failed
grant persistence therefore cannot reopen an old copy; successful reconciliation
clears the barrier only after the current connection reloads. Project catalogues
restored from disk are filtered through each current grant before they are
exposed. See [#368](https://github.com/PinedaTec-EU/LeonardoMD/issues/368) and
[PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369).

Keep async callback defaults in the public generic
`DirectEnrollmentClient.withRevocationRecheck` API as optional `nil` parameters
and resolve the normal STATUS behavior in its library body. Xcode 26.3 / Swift
6.2.4 can link incompatible context metadata for public async default-argument
closures across modules, aborting the test process with signal 6; the regression
is tracked by [#450](https://github.com/PinedaTec-EU/LeonardoMD/issues/450).

Peer upload manifests pin the original grant, proposal selection, and reader
capabilities. After an upgrade, a broader current grant or selection may resume
that upload only when it covers the persisted view; all reads, validation,
receipts, and acknowledgement continue under the saved narrower view. A
tombstone retains that manifest for idempotent acknowledgement and slot reuse,
so its serialized-size limit must allow both persisted selections. Validate the
payload, submitted marker, and manifest before deleting any staged file to keep
cleanup repeatable. See [#489](https://github.com/PinedaTec-EU/LeonardoMD/issues/489)
and [#490](https://github.com/PinedaTec-EU/LeonardoMD/issues/490).

Excluded extensions must be checked on the upload base and proposed snapshots
before acceptance can stage writes, then on the resolved result and transaction
journal before commit or crash recovery. This prevents a legacy or crafted peer
proposal from writing a format the receiving view excludes. See
[#491](https://github.com/PinedaTec-EU/LeonardoMD/issues/491).
