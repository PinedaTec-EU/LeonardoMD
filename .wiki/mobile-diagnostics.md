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
- Bilingual Guide v86 combines PR #369's actionable project-download errors,
  authorization boundaries and offline recovery with the localized scanner,
  settings and diagnostic-log guidance. Existing personal guide copies and
  practice answers remain untouched; exact package hashes and Help acceptance
  status are recorded in `.wiki/current-state.md`.

Source anchors: `Mobile/LittleLeonardo/MobileDiagnosticLog.swift`,
`Mobile/LittleLeonardo/MobileQRScanner.swift`,
`Mobile/LittleLeonardo/MobileLibraryView.swift`,
`Sources/LeonardoSync/DownloadLibrary.swift`,
`Sources/LeonardoSyncUI/RemoteDocumentPreview.swift`.

The current #380 diagnostic UI candidate is [PR #435](https://github.com/PinedaTec-EU/LeonardoMD/pull/435); stacked authorization recovery is in [PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369). The combined v86 guide also includes PR #445's editable local Mac names. Packaged v86 Help/practice acceptance remains pending while macOS is locked. The original physical large-image transfer criterion remains open; see [#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380).
