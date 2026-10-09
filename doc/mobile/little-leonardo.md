# Little Leonardo

Implementation tracking: [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92).

## Agreed product contract

Each project chooses direct read-only synchronization or Git editing. Git projects may choose direct mode. Only the direct service requires the desktop and mobile to share a private local network; Git can operate over the Internet.

The desktop service is explicitly enabled, off by default. Pairing supports a unique QR or IP/port and a cross-checked code. Projects are explicitly authorized. Device credentials stay in platform secure storage, outside portable configuration. Turning off the service retains mobile corpus; revocation requests deletion on the next reachable contact and rejects further document access. Offline deletion cannot be guaranteed before contact. Git copies are independent of direct revocation.

Direct snapshots include permitted documents/resources and open unsaved buffers. Mobile caches them for offline reading and explains the Git requirement when Edit is pressed. Both manual synchronization and a configurable interval are available; intervals operate while the iOS app can execute, without promising continuous background timers.

Git import selects a folder before transferring file contents and remembers it. Sparse checkout alone is insufficient: partial transfer must be supported by both server and iOS adapter. Never fall back silently to full clone. Hidden files, credentials, build outputs and path escapes are excluded. Offline creation, editing and deletion remain inside the selected corpus.

Send changes publishes a device-specific branch before sending an optional paired-desktop notification. Publication and notification are separate outcomes. Desktop also discovers branches by fetching, offers diffs and user-controlled reconciliation, and preserves unsaved desktop work. Mobile distinguishes local changes, sent work and integrated work. Further offline edits survive incorporation of a previous send; overlapping edits remain pending for desktop resolution.

## Implementation status

`LeonardoSync` is an independent shared SwiftPM library targeting macOS 14 and iOS 17. It currently contains corpus path/content limits, direct read-only and Git-editable offline state, atomic cache persistence and a project corpus reader with unsaved-buffer overlays. Its regression tests cover escapes, hidden/build exclusions, symlinks, case aliases, size limits, restart, deletion and later edits during integration.

The native `Mobile/LittleLeonardo.xcodeproj` target builds for iPhone/iPad on iOS 17+. It loads cached projects, reads UTF-8 documents, blocks direct-mode editing with an explanation, and supports Git-mode offline creation/editing/deletion. A fresh process on iPhone 17 Pro Max / iOS 26.5 displayed both cached synthetic projects. This proves local corpus loading, not network or Git transfer. Pairing consent policy, hashed authorization metadata and the Keychain adapter are implemented. Their transport/UI wiring is pending. Desktop network-service lifecycle, pairing screens, credential-storage runtime validation, mobile revocation cleanup, real Git adapter, desktop reconciliation interface and end-to-end evidence remain pending. No partial-clone support is claimed for an iOS Git library until demonstrated with a large-repository fixture.

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

Raw bearer credentials are generated with the platform secure random source and stored by `SecureCredentialStore` in device-only, non-synchronizing Keychain entries. The registry persists credential hashes in a bounded, atomic host-local file with owner permissions. The shared HTTPS transport now verifies a certificate pin and its explicit trust anchor before credential exchange. Native enrollment screens must obtain that pin from QR or an independently calculated cross-check; those screens are pending. No plaintext LAN access is introduced.

Filesystem adapters resolve the trusted configured directory and preserve the final entry for symlink checks. Do not reject legitimate host-root aliases or normalize an untrusted descendant before checking it. Regression: [#96](https://github.com/PinedaTec-EU/LeonardoMD/issues/96).

## HTTPS transport checkpoint

`LeonardoSyncTransport` uses Network.framework for an HTTP/1.1 TLS listener bound to one explicit private/local IP literal, plus a pinned URLSession client. It rejects wildcard/public bindings, redirects, duplicate or ambiguous framing headers, oversized requests/responses and wrong certificate pins. Certificate trust retains anchored signature/validity evaluation. Client response bytes are bounded while streaming. Header and operation deadlines and connection limits bound work. Logs contain method/status/lifecycle fields, not credentials or corpus contents.

`DirectSyncAuthority` persists consent changes before publishing them, exposes only granted project descriptors, and rechecks authorization after asynchronous corpus reads. `DirectHTTPSRouter` exposes pairing request, own-device status and authorized snapshot routes; approval is exclusively a desktop-side application action. A revoked device receives cleanup status, but no snapshot.

Real loopback TLS regressions exercise disabled service, pending request, approval, unsaved-buffer snapshot transfer, revocation, wrong pin and response bounds. Additional domain tests cover failed persistence and revocation during a suspended snapshot read. These prove transport/application contracts, not end-user desktop/iOS pairing or physical-device networking.

The manual comparison code binds the observed certificate fingerprint, client credential digest and request ID. Both UIs must compute/display their own value; copying the remote code would invalidate the protection. Preventive correction: [#97](https://github.com/PinedaTec-EU/LeonardoMD/issues/97). Streaming requests explicitly use the canonical TLS task delegate: [#98](https://github.com/PinedaTec-EU/LeonardoMD/issues/98).

Desktop integration now includes the default-off global preference, explicit project grants, QR generation, device approval/rejection/revocation and service lifecycle wiring. The server identity is an encrypted owner-only PKCS#12 archive with its password in device-local Keychain; missing credentials fail rather than silently rotating the pin. Three desktop adapter tests cover restart identity continuity, actual pinned TLS, missing-password preservation and no identity provisioning while disabled. Two QR tests cover round-trip, expiry and malformed/external endpoint rejection. Native end-user UI acceptance, QR/manual enrollment on iOS, mobile secure-credential use and cache cleanup, and manual/configured-interval refresh remain pending. Git transport, publication/notifications and desktop reconciliation remain separate unfinished requirements.

## Mobile enrollment checkpoint

The iOS library accepts a pasted QR link, computes its comparison code independently and lets the user request desktop consent. Manual refresh downloads only approved project snapshots using the pinned HTTPS client. Connection metadata survives relaunch without retaining QR invitation secrets; credentials live in device-only Keychain. Authorized direct snapshots are cached for offline reading. Revocation removes owned caches and hides an open reader; disabling or unreachable service retains the cache. A real TLS regression covers pending/approved/revoked states and unsaved-buffer download. Simulator compilation passes, but native interaction, durable mobile cleanup/retry evidence, camera scanning and IP/port manual pairing are still pending. Direct refresh supports manual operation or a persisted 1/5/15/30/60-minute interval while the app is active; background execution is not assumed. Interval and native cleanup behavior still require runtime acceptance.

## Offline archive regression

[#99](https://github.com/PinedaTec-EU/LeonardoMD/issues/99) records a valid near-limit corpus that could be saved but not reopened. The encoded bound now accounts for all three base/current/published collections, base64 expansion and escaped metadata, with checked integer arithmetic. Paths are bounded to 4 KiB, revisions to 256 bytes and stored project names to 1 KiB to make the metadata allowance finite. Save and load use the same encoded bound. The published-baseline restart regression and unrepresentable-limit rejection pass.

## Camera scanner checkpoint

The pairing screen can scan a QR with Apple VisionKit. Camera permission is requested only after the user opens the scanner. Unsupported/restricted hardware offers pasted-link enrollment; cancellation dismantles the scanner and stops capture. Only a valid, unexpired Little Leonardo QR is accepted, and reading it does not automatically authorize or start the network connection. The iOS Simulator UI test opens the scanner, verifies its unavailable fallback, cancels it, and verifies no connection request was initiated. Its real screenshot was inspected from `/tmp/little-camera-ui.xcresult`. Physical-camera capture and permission-denial behavior are implemented but not verified on a physical device.
