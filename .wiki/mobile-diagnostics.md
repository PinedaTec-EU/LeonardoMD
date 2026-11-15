# Little Leonardo diagnostics

Little Leonardo failures use a localized short message, a unique `LL-…`
reference and one acknowledgement action. `MobileErrorNotice` records a safe
category or bounded network facts in `MobileDiagnosticLog`; the log is
main-actor serialized, local-only, limited to 120 entries / 64 KiB and stored
under the app cache excluded from backups. The app does not upload it.

- `MobileLibraryView` exposes the localized **Ajustes de sincronización / Sync
  settings** route and **Ver log / View log**. The selected
  reference lets the user match an alert with a recent log line.
- `MobileQRScanner` routes malformed or expired recognized invitations through
  the same localized notice with operation `scanner`. The log excludes the QR
  payload, endpoint and token. See [#451](https://github.com/PinedaTec-EU/LeonardoMD/issues/451).
- `DownloadLibrary.openResult` joins an existing same-file transfer so its
  callers share one failure reference. A new attempt clears the previous
  reference before a cache read. When a presentation handler is configured,
  `RemoteDownloadFailure` carries that attempt's message into the preview;
  without one, `openResult` preserves the original fetch or cache error type.
  Tests cover both public error behavior, retry isolation and shared in-flight
  diagnostics.
- Bilingual Guide v77 explains scanned QR failures. It uses a new personal-copy
  directory and leaves saved v76 guides and practice answers unchanged.

Source anchors: `Mobile/LittleLeonardo/MobileDiagnosticLog.swift`,
`Mobile/LittleLeonardo/MobileQRScanner.swift`,
`Mobile/LittleLeonardo/MobileLibraryView.swift`,
`Sources/LeonardoSync/DownloadLibrary.swift`,
`Sources/LeonardoSyncUI/RemoteDocumentPreview.swift`.

The current #380 diagnostic UI candidate is [PR #435](https://github.com/PinedaTec-EU/LeonardoMD/pull/435).
Its physical large-image transfer criterion remains open; see
[#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380).
