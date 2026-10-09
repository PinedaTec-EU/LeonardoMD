# Changes

- 2026-10-07: Initial native macOS implementation under [issue #1](https://github.com/PinedaTec-EU/LeonardoMD/issues/1). Added standalone viewer and focus story, offline opt-in engines, and premium controls. Native QA registered [bug #2](https://github.com/PinedaTec-EU/LeonardoMD/issues/2) for missing Mermaid labels and [bug #3](https://github.com/PinedaTec-EU/LeonardoMD/issues/3) for relative images; corrections and final evidence remain part of the same PR.

- 2026-10-07: [#25](https://github.com/PinedaTec-EU/LeonardoMD/issues/25) closes symlink search escapes and target mutations with explicit omission/rejection policy and actual link fixtures; [#26](https://github.com/PinedaTec-EU/LeonardoMD/issues/26) requires confirmation before document-authored local links activate system handlers. ADR/validation and this memory record the policies. [#9](https://github.com/PinedaTec-EU/LeonardoMD/issues/9) remains open for the mouse/accessibility discrepancy despite a passing fresh-process keyboard flow.
- 2026-10-07: #15 adds Sparkle menu checks and signed release preparation, tracked by https://github.com/PinedaTec-EU/LeonardoMD/issues/15.
- 2026-10-07: Added the approved pencil-lettered About banner, reusable native About window and runtime bundle version display for [#27](https://github.com/PinedaTec-EU/LeonardoMD/issues/27), initially stacked on MVP PR #8 and now integrated through PR #28.
- 2026-10-07: Added per-session document tabs, local Markdown drops, header location actions and cross-tab close/file-operation protection for [#19](https://github.com/PinedaTec-EU/LeonardoMD/issues/19), initially stacked on #8, now targeting main. Independent native view ownership preserves editor undo and reading position without copying document state between tabs.

- 2026-10-07: Refreshed #19 on main with #27/#31 integrated. Added actual native URL-provider regression coverage and constrained sidebar relocation to project-owned sources; document drops remain non-destructive.

- 2026-10-07: Added single-instance ownership, acknowledged launch forwarding and external document tab routing for [#22](https://github.com/PinedaTec-EU/LeonardoMD/issues/22), now targeting main after #21 integration. Native QA covers repeated and simultaneous executable launches plus Launch Services reopen/open-document events.


- 2026-10-07: Single-instance integration exposed a Git output completion race in hosted CI. [#35](https://github.com/PinedaTec-EU/LeonardoMD/issues/35) drains both subprocess streams through EOF before returning, with short/large-output and failed-launch regressions.

- 2026-10-08: Implemented preview tag pills and current-project `tag:` search for [#20](https://github.com/PinedaTec-EU/LeonardoMD/issues/20). Shared the metadata parser with Core; added extraction, streaming-search, AppSession and real WebKit regressions plus reproducible CI captures.

- 2026-10-08: Revalidated [#9](https://github.com/PinedaTec-EU/LeonardoMD/issues/9) and [#31](https://github.com/PinedaTec-EU/LeonardoMD/issues/31) on 0.1.0 build 1 (`041c63b`) and closed both as no longer reproduced in the tested context. Corrected project root alias handling for [#33](https://github.com/PinedaTec-EU/LeonardoMD/issues/33), preserving symlink-component checks.

- 2026-10-08: Prepared shared release-ledger adoption from seed 0.1.56, per-PR deltas, canonical packaged metadata and referenced release skills. Central automatic writers and CI access remain activation dependencies. Tracking: [#38](https://github.com/PinedaTec-EU/LeonardoMD/issues/38).

- 2026-10-08: Aligned #38 with the shared non-.NET `release.feature.build` semantics and added success-only Swift compilation recording; deltas count recorded commands rather than PRs. [#38](https://github.com/PinedaTec-EU/LeonardoMD/issues/38).
- 2026-10-08: Reopened [#22](https://github.com/PinedaTec-EU/LeonardoMD/issues/22): product-wide ownership replaces bundle-specific ownership; forwarded document batches reactivate after loading. Old QA executables require a graceful one-time quit.

- 2026-10-08: Reconciled #38 with integrated signed-update packaging and product-wide instance ownership. Sparkle preserves ledger metadata and rejects release version/build overrides. [#38](https://github.com/PinedaTec-EU/LeonardoMD/issues/38).

- 2026-10-08: Added English-default global language selection and English/Spanish resource catalogs for [#57](https://github.com/PinedaTec-EU/LeonardoMD/issues/57).
- 2026-10-08: Verified central policy dispatch and protected serial materialization under [#38](https://github.com/PinedaTec-EU/LeonardoMD/issues/38), then published stable [0.1.64](https://github.com/PinedaTec-EU/LeonardoMD/releases/tag/v0.1.64) from `3aebf44` with Developer ID, Apple notarization/stapling and signed update assets. [#61](https://github.com/PinedaTec-EU/LeonardoMD/issues/61) records automatic generated-branch cleanup; pinedatec-ci#279 remains the separate automatic merge permission gap.

- 2026-10-08: refreshed the immutable engine to integrated `fdc500c76d3f42f1162cd48ad1997601cce06336`, correcting accepted-notes proposal body outputs ([central #289](https://github.com/PinedaTec-EU/pinedatec-ci/issues/289)); live notes completion stays under [#38](https://github.com/PinedaTec-EU/LeonardoMD/issues/38).

- 2026-10-08: Added the ARX-style source-merge dispatch adapter and documented automatic App version/prepared-note writes separately from accepted publication. [#69](https://github.com/PinedaTec-EU/LeonardoMD/issues/69).

- 2026-10-09: Added the native QA launch convention to root `AGENTS.md` for [#80](https://github.com/PinedaTec-EU/LeonardoMD/issues/80): XCTest uses a test runner; visual QA preserves the real packaged executable, checks dependencies and verifies fresh-process readiness while respecting product-wide instance ownership. Original harness correction and runtime validation remain pending.

- 2026-10-09: #80 QA packaging now copies the real signed bundle via `scripts/qa-bundle.py`; `launch.sh --qa` uses it, and build packaging rejects test-runner executables/XCTest linkage. See https://github.com/PinedaTec-EU/LeonardoMD/issues/80.

## 2026-10-09 — Little Leonardo work in progress

2026-10-09 — #92 / PR #93: registered [#112](https://github.com/PinedaTec-EU/LeonardoMD/issues/112) after the real iOS Git acceptance flow exposed a SwiftUI readiness-publication warning. `MarkdownPreviewController` now defers, deduplicates and generation-checks WebKit readiness callbacks; focused renderer tests cover ordering and stale hosts. Validation is pending the parent build.

[#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92) defines the iOS companion, direct read-only LAN snapshots and folder-scoped Git editing. The new standalone `LeonardoSync` target provides corpus boundaries, offline state/persistence and safe project snapshot reading. See [mobile contract and pending implementation](../doc/mobile/little-leonardo.md). This does not establish a runnable iOS app or completed synchronization.

Native iOS checkpoint for [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92): shared `LittleLeonardo` Xcode scheme builds for iOS Simulator; a fresh process on iPhone 17 Pro Max loads synthetic cached direct/Git projects. Native local reading and Git-mode offline mutation controls exist; no network/Git synchronization claim. CI includes the iOS build and the ledger scopes `Mobile/**`.

Pairing checkpoint for [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92): explicit consent/project grants, one-use expiring invitations, persistent revocation, hashed authorization metadata and a Keychain adapter. Fourteen sync regressions pass; iOS compiles. TLS/network and UI wiring are still pending. Host-directory alias regression tracked in [#96](https://github.com/PinedaTec-EU/LeonardoMD/issues/96).
- 2026-10-09: Removed the redundant Preferences action and footer spacer from the document outline. Preferences remain in the application menu (⌘,). Tracking: [#88](https://github.com/PinedaTec-EU/LeonardoMD/issues/88).

HTTPS checkpoint for [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92): explicit-IP TLS listener, pinned/anchored client, bounded framing/streaming, durable consent authority and authorized snapshot routes. Twenty-two focused regressions pass, including real loopback pairing/approval/unsaved snapshot/revocation and certificate mismatch. Full macOS suite and iOS compilation passed before final logging-only adjustment. Manual comparison identity binding tracked in [#97](https://github.com/PinedaTec-EU/LeonardoMD/issues/97); streaming delegate correction in [#98](https://github.com/PinedaTec-EU/LeonardoMD/issues/98). Native service/enrollment and Git integration remain pending.

2026-10-09 — #92 / PR #93: added desktop default-off service preferences, explicit project/device consent UI and persistent TLS identity provisioning. Focused desktop identity/lifecycle tests (3) and QR boundary tests (2) pass. Native pairing acceptance and Git transport/reconciliation remain unfinished; this checkpoint is not feature completion.

2026-10-09 — #92 / PR #93: added typed pinned enrollment client and iOS pasted-QR pairing/manual refresh integration with device-only credentials and persisted connection ownership. Real TLS consent/download/revocation regression passes; iOS Simulator target compiles. Camera/manual-address pairing, interval refresh, native UI acceptance and Git remain pending.

2026-10-09 — #92 / PR #93: added native VisionKit QR scanner, on-demand camera permission and cancellable unavailable fallback. Simulator UI test passes with inspected screenshot; physical scanning remains unverified. Reproduced and registered [#99](https://github.com/PinedaTec-EU/LeonardoMD/issues/99), then fixed offline encoded-baseline bounds; nine corpus tests pass, including restart and integer-overflow regressions.

2026-10-09 — #92 / PR #93: implemented private-IP/port manual enrollment. Certificate discovery cancels before HTTP and leaves authentication to pinned cross-code desktop consent. Five desktop TLS/enrollment tests and two native Simulator pairing UI tests pass. Full product pairing/revocation and Git remain pending.

2026-10-09 — #92 / PR #93: localized desktop mobile-service consent/preferences in English and Spanish. Nine localization checks pass with inspected native disabled-panel captures; seven configuration-store tests pass including default-off migration and stale-window consent preservation. No real user configuration or packaged single-instance app was used.

2026-10-09 — #92 / PR #93: ported the shared native WebKit Markdown renderer to iOS and added immutable corpus-memory image delivery with remote-image blocking. Twelve renderer tests, a real WebKit asset-removal test and an inspected native iOS heading/table/image/source-toggle fixture test pass. Mobile hyperlinks and complete enrollment/revocation acceptance remain pending; mobile Git is still unimplemented.

2026-10-09 — #92 / PR #93: introduced native `LeonardoGit` bounded pkt-line/capability foundation. Four tests pass against malformed framing and real upload-pack advertisements/metadata transfer; a clean receiver proves no blobs were transferred from a document + 16 MiB code fixture. iOS builds the module. No complete Git transport, folder import or publication is claimed.

2026-10-09 — #92 / PR #93: added native Git-v2 branch/symbolic/unborn reference discovery and shared negotiated object-ID validation. Six wire tests pass against real SHA-1/SHA-256 repositories and ref-format validation; duplicate/injected replies and unexpected categories are rejected/filtered. No folder import or complete mobile Git synchronization is claimed.

2026-10-09 — #92 / PR #93: added bounded Git fetch envelope/sideband decoding with ordered sections, SHA-1/SHA-256 pack checksum validation and stateless response-end support. Eight Git tests pass against real and corrupted replies; iOS compilation passes. Compressed-object/delta decoding and working Git synchronization remain unfinished.

2026-10-09 — #92/PR #93: combined delta181 validates 331 XCTest cases and twelve renderer tests. Actual HTTPS wakeup receipt now awaits atomic persistence and retries after recovered storage; review notices survive failed project navigation. Direct-to-Git notification mappings are removed on revocation/scope changes. Shared NativeViewCaptureSupport resets post-layout geometry, eliminating repeated partial bitmap artifacts; inspected native review labels are complete in Spanish at960points. Delivery gates remain current-head CI and strict judgment.

2026-10-09 — #92/PR #93: delta184 passes 337 XCTest cases plus twelve renderer tests, with ten opt-in native controller/capture cases separately. #116 binds reviewed branch/commit/remote through selection changes, application and durable restart retry. #117 uses fresh lstat for mutable notification mapping paths; #118 waits for the exact editor value before UI saving; #119 propagates the workspace controller into Git review. #107 rejects missing wakeup sinks and awaits shutdown persistence inside the termination barrier, including independently flushing after a failed service stop.

## 2026-10-09 — trusted ledger scope correction

PR #93 restores the base release-ledger configuration after the exact-head central policy rejected the Mobile/** expansion. The earlier checkpoint describing mobile ledger coverage is superseded: this source PR has its valid delta through shared versioned paths, but future mobile-only automatic detection requires a separately authorized policy operation. Tracked in [issue #120](https://github.com/PinedaTec-EU/LeonardoMD/issues/120). Native acceptance source hashes and captures are unchanged.
