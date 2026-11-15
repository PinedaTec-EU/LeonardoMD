# Little Leonardo diagnostics

Little Leonardo failures use a localized short message, a unique `LL-…`
reference and one acknowledgement action. `MobileErrorNotice` records a safe
category or bounded network facts in `MobileDiagnosticLog`; the log is
main-actor serialized, local-only, limited to 120 entries / 64 KiB and stored
under the app cache excluded from backups. The app does not upload it.

- `MobileSyncPreferencesView` exposes **Ver log / View log**. The selected
  reference lets the user match an alert with a recent log line.
- `MobileQRScanner` routes malformed or expired recognized invitations through
  the same localized notice with operation `scanner`. The log excludes the QR
  payload, endpoint and token. See [#451](https://github.com/PinedaTec-EU/LeonardoMD/issues/451).
- `DownloadLibrary.openResult` joins an existing same-file transfer so its
  callers share one failure reference. A new attempt clears the previous
  reference before a cache read; `RemoteDownloadFailure` carries the reference
  created for that exact failure into the preview. Tests cover retry isolation
  and shared in-flight diagnostics.
- Bilingual Guide v80 in stacked PR #369 combines scanned-QR recovery with
  actionable project-download errors and authorization boundaries. A saved v79
  personal copy and its separate practice answers remain untouched; EN/ES package
  hashes and current-candidate status are in `.wiki/current-state.md`.

Source anchors: `Mobile/LittleLeonardo/MobileDiagnosticLog.swift`,
`Mobile/LittleLeonardo/MobileQRScanner.swift`,
`Mobile/LittleLeonardo/MobileSyncPreferencesView.swift`,
`Sources/LeonardoSync/DownloadLibrary.swift`,
`Sources/LeonardoSyncUI/RemoteDocumentPreview.swift`.

The current #380 diagnostic UI candidate is [PR #435](https://github.com/PinedaTec-EU/LeonardoMD/pull/435); stacked authorization recovery is in [PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369). The merged local suite passes, exact-head CI for #369 is running, and packaged v80 Help/practice acceptance remains pending while macOS is locked. The original physical large-image transfer criterion remains open; see [#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380).
