# Little Leonardo

Implementation tracking: [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92).

## Agreed product contract

Each project chooses direct read-only synchronization or Git editing. Git projects may choose direct mode. Only the direct service requires the desktop and mobile to share a private local network; Git can operate over the Internet.

The desktop service is explicitly enabled, off by default. Pairing supports a unique QR or IP/port and a cross-checked code. Projects are explicitly authorized. Device credentials stay in platform secure storage, outside portable configuration. Turning off the service retains mobile corpus; revocation requests deletion on the next reachable contact and rejects further document access. Offline deletion cannot be guaranteed before contact. Git copies are independent of direct revocation.

Direct snapshots include permitted documents/resources and open unsaved buffers. Mobile caches them for offline reading and explains the Git requirement when Edit is pressed. Both manual synchronization and a configurable interval are available; intervals operate while the iOS app can execute, without promising continuous background timers.

Git import selects a folder before transferring file contents and remembers it. Sparse checkout alone is insufficient: partial transfer must be supported by both server and iOS adapter. Never fall back silently to full clone. Hidden files, credentials, build outputs and path escapes are excluded. Offline creation, editing and deletion remain inside the selected corpus.

Send changes publishes a device-specific branch before sending an optional paired-desktop notification. Publication and notification are separate outcomes. Desktop also discovers branches by fetching, offers diffs and user-controlled reconciliation, and preserves unsaved desktop work. Mobile distinguishes local changes, sent work and integrated work. Further offline edits survive incorporation of a previous send; overlapping edits remain pending for desktop resolution.

## Implementation status

`LeonardoSync` is an independent Foundation-only SwiftPM library targeting macOS 14 and iOS 17. It currently contains corpus path/content limits, direct read-only and Git-editable offline state, atomic cache persistence and a project corpus reader with unsaved-buffer overlays. Its regression tests cover escapes, hidden/build exclusions, symlinks, case aliases, size limits, restart, deletion and later edits during integration.

The native `Mobile/LittleLeonardo.xcodeproj` target builds for iPhone/iPad on iOS 17+. It loads cached projects, reads UTF-8 documents, blocks direct-mode editing with an explanation, and supports Git-mode offline creation/editing/deletion. A fresh process on iPhone 17 Pro Max / iOS 26.5 displayed both cached synthetic projects. This proves local corpus loading, not network or Git transfer. Pairing consent policy, hashed authorization metadata and the Keychain adapter are implemented. Their transport/UI wiring is pending. Network service, pairing screens, credential-storage runtime validation, revocation transport, real Git adapter, desktop reconciliation interface and end-to-end evidence remain pending. No partial-clone support is claimed for an iOS Git library until demonstrated with a large-repository fixture.

## Boundaries to retain

- Selected scope governs reads, edits and publication, not just the mobile file browser.
- Publication must succeed before notification; notification delivery never substitutes for Git discovery.
- Integration updates must identify the published commit whose work was accepted, rather than trusting any new remote revision.
- Invalid or oversized snapshots fail atomically rather than silently delivering an incomplete corpus.
- Reconciliation must preserve local work; neither desktop buffers nor mobile edits are implicitly discarded.

## Native iOS build

Open `Mobile/LittleLeonardo.xcodeproj` and select the shared `LittleLeonardo` scheme. Simulator builds do not require signing credentials:

```sh
xcodebuild -project Mobile/LittleLeonardo.xcodeproj -scheme LittleLeonardo -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/little-ios CODE_SIGNING_ALLOWED=NO build
```

CI builds this target alongside the macOS suite. Mobile sources are included in the release ledger's versioned path scope. Device installation and distribution require the owner's Apple signing configuration; neither is claimed by simulator validation.

## Pairing policy checkpoint

`PairingRegistry` requires desktop consent with matching comparison code and a non-empty project grant. QR invitations expire after five minutes and are single-use; regenerating a QR invalidates the prior invitation. Manual pairing requests require the same explicit desktop consent. Authorization checks bind a device credential to the approved projects. Revocation persists, returns cleanup status only to the matching credential, and prevents document access. Disabling the service clears pending invitations/requests while preserving paired-device metadata.

Raw bearer credentials are generated with the platform secure random source and stored by `SecureCredentialStore` in device-only, non-synchronizing Keychain entries. The registry persists credential hashes in a bounded, atomic host-local file with owner permissions. The transport must enforce TLS server verification before any credential exchange; that transport is not implemented yet. No certificate-validation bypass or plaintext LAN access is introduced by this checkpoint.

Filesystem adapters resolve the trusted configured directory and preserve the final entry for symlink checks. Do not reject legitimate host-root aliases or normalize an untrusted descendant before checking it. Regression: [#96](https://github.com/PinedaTec-EU/LeonardoMD/issues/96).
