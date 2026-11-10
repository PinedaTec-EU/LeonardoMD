# Changes

- 2026-11-06: [#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380), [PR #382](https://github.com/PinedaTec-EU/LeonardoMD/pull/382): pinned HTTPS `URLError`s retain their domain, code and other metadata while adding an operation/HTTP/byte diagnostic to the existing localized error. A real TLS response-cut test verifies partial bytes without leaking URL/credentials/IDs/content. The owned iOS 27.0 Simulator status-error alert and full recovery flow pass after isolating stale test peer data; the physical 338,658-byte image cause remains unconfirmed. Help advances to v22, preserving personal copies v20/v21 allocated to parallel work; TestFlight and issue closure remain pending.

- 2026-11-05: [#350](https://github.com/PinedaTec-EU/LeonardoMD/issues/350) completion-winning cancellation correction: a remote completion observed while Mac cancellation is pending is persisted as `completedBeforeCancellation`, discarded from review/save, and remains terminal across restart. Focused `RubricCaptureTests` passes at delta 36 (16 tests); full `swift test` passes at delta 37 (364 XCTest, 30 expected skips, 42 Swift Testing, zero failures). Final native evidence maps to source `7dbf8bdfacc4e4d5ba4f015933a62c4c12e382ee`.

- 2026-11-05: [#319](https://github.com/PinedaTec-EU/LeonardoMD/issues/319) extracts macOS source sharing into a required optional per-user helper; app manages registration/master consent, outbound operations fail closed and saved-file snapshots survive editor exit. Later owner-authorized native acceptance validates registration, reading after owner-editor exit, launchd helper restart and disable/offline behavior; no physical reboot is claimed.

- 2026-10-20: [#249](https://github.com/PinedaTec-EU/LeonardoMD/issues/249) retires the proprietary mobile Git implementation and exclusive dependencies. iOS retains direct read-only snapshots and recovery exports of old corpus states; desktop direct synchronization and installed-system-Git tools are preserved. Persistence also rejects overwriting recovery archives independently of library memory ([#251](https://github.com/PinedaTec-EU/LeonardoMD/issues/251)). Native/automated evidence is tracked on the source PR; no Windows implementation or release is claimed.

- 2026-10-20: [#244](https://github.com/PinedaTec-EU/LeonardoMD/issues/244) adds ADR 0002 comparing custom Git, libraries, provider APIs, desktop mediation and reduced scope. Owner selected iOS read-only/offline cache and editable macOS/Windows desktop synchronization, replacing the first draft's editable-mobile proposal. Git retirement, legacy recovery and Windows conformance remain pending; existing runtime and in-flight work are preserved.

- 2026-10-20: [#208](https://github.com/PinedaTec-EU/LeonardoMD/issues/208), [PR #213](https://github.com/PinedaTec-EU/LeonardoMD/pull/213): Preview table drag controls commit point geometry through a scoped native transaction, migrate Markdown safely to MDLF, and persist content-minimum row/table heights. Source-bound geometry and matching Swift/plugin schemas prevent stale layout and silent metadata loss. Native and browser QA details: [table resizing](../doc/validation/table-resizing.md).

- 2026-10-15: [#146](https://github.com/PinedaTec-EU/LeonardoMD/issues/146): Visible front matter uses a left border bound to the same `--ld-heading` token as document titles.

- 2026-10-14: [#128](https://github.com/PinedaTec-EU/LeonardoMD/issues/128), [PR #129](https://github.com/PinedaTec-EU/LeonardoMD/pull/129): Interface Language and its global-scope note now live inside General, before Palette; the shared language binding is unchanged.

- 2026-10-12: [#123](https://github.com/PinedaTec-EU/LeonardoMD/issues/123), [PR #124](https://github.com/PinedaTec-EU/LeonardoMD/pull/124): Added global Updates preferences, explicit stable/beta choice, common stable trust root, atomic beta-feed composition and a release acceptance matrix. Durable pending-decision and canonical-tag regressions are tracked in [#125](https://github.com/PinedaTec-EU/LeonardoMD/issues/125) and [#126](https://github.com/PinedaTec-EU/LeonardoMD/issues/126). Hosted acceptance remains separate in #15/#84.

- 2026-10-10: [#121](https://github.com/PinedaTec-EU/LeonardoMD/issues/121) now has a reproducible specific-failure guarantee: normal upload/receive sessions have bounded post-EOF diagnostics; injected publication failure preserves exact journal/ref bytes and requires confirmed process/stream cleanup before one identical retry. Compile delta193 passes 340 XCTest cases (ten optional skips) and twelve renderer tests. Normal real Git fetch/push also verifies every launched session's exit, separate stream EOF and single handler completion. Original intermittent causality remains unproven; this correction meets the diagnostic alternative without raising transport timeout or skipping the test. Native Git repetition passes at delta192 (138.046s UI, 143.760s server), with identical native fixture/mobile/shared sources through delta193 and all 185 production/UI hashes still matching both capture manifests. Current-head CI and fresh strict judgment remain delivery gates.

- 2026-10-09: Hardened the real Git SSH fixture for [#121](https://github.com/PinedaTec-EU/LeonardoMD/issues/121): session phases now expose handler, request, process, pipe and channel lifecycle; process stop terminates before closing stdin and bypasses queued writes; cleanup and real fetch/receive regressions pass with one native fixture skip.

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

## 2026-10-09 — process-exit and native-history test checkpoint

Compile delta189 passes 338 XCTest cases (ten optional skips) and twelve renderer tests. The real Git SSH fixture uses a termination handler installed before process launch, with balanced completion branches and PID/live-state diagnostics, rather than waitUntilExit. The real child cancellation regression and scoped fetch/push pass. The [#95](https://github.com/PinedaTec-EU/LeonardoMD/issues/95) recents test now waits for observable AppKit history transitions. [#121](https://github.com/PinedaTec-EU/LeonardoMD/issues/121) remains open because its original intermittent CI stall has not been conclusively attributed. No production/mobile source changed in this test refinement.

## 2026-10-09 — live mobile document deletion checkpoint

[Issue #122](https://github.com/PinedaTec-EU/LeonardoMD/issues/122) separates editor updates from explicit creation. The view and editing lease use the live scoped corpus; save rechecks Git mode, scope and path presence at the mutation boundary. Native SSH acceptance keeps a document open while integration deletes it, verifies unavailable state and disabled Edit, then verifies a second publication preserves deletion. Compile delta190 passes 338 XCTest cases (ten optional skips) and twelve renderer tests. Signed iOS build and final Git UI/server acceptance pass (121.599s/139.294s). Final direct UI/server acceptance also passes (53.320s/53.364s), with independently absent revoked corpus/grant. Captures show removed/revoked documents with synchronization ready, Edit disabled and no masking alert. Both provenance manifests match all 185 current source hashes. Final-head hosted CI and fresh strict judgment remain delivery gates.

## 2026-10-12 — explicit release progression

Owner clarification for [#123](https://github.com/PinedaTec-EU/LeonardoMD/issues/123), PR #124: normal publication requires accepted PR, hosted validated beta, then stable from that functional source with a new higher build. A repository-local release skill records candidate-specific explicit beta exceptions without waiving CI/review, trust or distribution validation. The shared merge policy remains unchanged; no current publication/merge exception is authorized.

## 2026-10-12 — published channel-selector beta

[Beta 0.1.348](https://github.com/PinedaTec-EU/LeonardoMD/releases/tag/v0.1.348) from materialized source `319e193` is Developer ID signed/notarized/stapled and publicly Ed25519-verified. The combined beta feed is reachable. Real Sparkle update from a controlled signed/notarized v0.1.337 starting copy installed and relaunched 0.1.348; Preferences channel selection and stable waiting/beta no-update pass. The owner authorized normal app closure; `/Applications` installation is preserved. [#15 hosted evidence](https://github.com/PinedaTec-EU/LeonardoMD/issues/15#issuecomment-6124736089) records limits. PR #127 prepares a release-only promotion input and one successful packaging build delta within existing scripts scope, without app/dependency changes or a resolved-version edit. Stable publication remains pending.

## 2026-10-14 — table width comments

[#130](https://github.com/PinedaTec-EU/LeonardoMD/issues/130), proposed in
[PR #131](https://github.com/PinedaTec-EU/LeonardoMD/pull/131): preceding
`leonardo:table` comments configure validated `ch`/`auto` columns while keeping
standard GFM syntax. Normal tables preserve words; both paths scroll within
the preview. Native WebKit width, scope, invalid-input, update, dark/light and
narrow-window checks pass; full Swift validation passes. See [table layout](table-layout.md).
Integration and publication are separate gates.

## 2026-10-15 — Markdown default application choice

[#133](https://github.com/PinedaTec-EU/LeonardoMD/issues/133), proposed in
[PR #134](https://github.com/PinedaTec-EU/LeonardoMD/pull/134): the primary
process offers a Markdown-only default association after initial Finder opens.
`MarkdownAssociations` owns once-per-process policy and Mac-global suppression;
`WorkspaceMarkdownAssociationDriver` isolates Launch Services and rejects
unregistered Markdown instead of falling back to plain text. General preferences
shows status and exposes manual change/re-enable even in project scope.
QA identities and non-app test executables cannot modify associations.
Native visual tests use a fake driver and isolated preferences; they do not prove
a new packaged process or actual system-consent interaction.
Local cleanup of 33 old registrations is recorded in
[#135](https://github.com/PinedaTec-EU/LeonardoMD/issues/135); files and the
running installed app were preserved. Rediscovery can register old copies again.

- [#137](https://github.com/PinedaTec-EU/LeonardoMD/issues/137): typed favorites live in global preferences independently of recents. Membership merges preserve independent window changes; `SessionFavorites` shares actions between native `FavoritesMenu` and the scrollable `WelcomeView` / `SavedItemsView`. See [behavior and validation](../doc/validation/favorites/README.md).

## 2026-10-18 — Compilation count adapter

The shared compilation-count skill and `.skills/compilation-count.json` select
command eligibility and the existing counter/recorder. Historical allocations
and delivery-only identifiers are preserved. Tracking: [#163](https://github.com/PinedaTec-EU/LeonardoMD/issues/163).

- 2026-10-19: Open Leonardo MDLF/MDLR/MDLZ implementation and agent plugins started under [#167](https://github.com/PinedaTec-EU/LeonardoMD/issues/167), [PR #168](https://github.com/PinedaTec-EU/LeonardoMD/pull/168). Contract, native integration, transport and validation are tracked in [format context](leonardo-format.md).
## 2026-10-19 — Preferences scope containment

General and Extensions now own their Global / This project header inside the tab content, keeping the window header and navigation stationary. General puts palette/paper (and project-only Git) first, with language, non-project viewing settings and Markdown associations in separate Mac-wide sections. Storage behavior and themes are unchanged. The owner selected Product Design mockup 2; misleading OS-wide language copy in that generated target is corrected in the implementation. Tracking: [#173](https://github.com/PinedaTec-EU/LeonardoMD/issues/173). Owner-authorized fresh packaged startup and native five-tab/scope/localization QA now pass; source/global/project persistence and extension inheritance were exercised on a synthetic project. Full local suite: 392 cases, 15 optional skips, zero failures. Selected-target and navigation comparisons are in `design-qa.md`; CI/review/integration state remains on the issue/PR.

- #185: The tab bar gear beside New tab opens the active session’s existing preferences sheet; it shares the compact button style and closing guard. Tracking: https://github.com/PinedaTec-EU/LeonardoMD/issues/185.

- 2026-10-20: README now leads with signed/notarized macOS downloads and product usage; detailed usage, table syntax and contributor diagnostics/QA move to `doc/user-guide.md`, `doc/table-widths.md` and `doc/development.md`. Keep current package versions in GitHub Releases rather than historical baseline text. [#218](https://github.com/PinedaTec-EU/LeonardoMD/issues/218).

- 2026-10-20: [#223](https://github.com/PinedaTec-EU/LeonardoMD/issues/223) separates dynamic latest-stable discovery from beta-only forms, records owner-confirmed update installation with #202 termination limits, and standardizes recent release notes in English with separate publication evidence.

- 2026-10-21: [#263](https://github.com/PinedaTec-EU/LeonardoMD/issues/263) adds opt-in explicit macOS processes, principal Finder routing/re-election, process-lifetime hierarchical path ownership, shared-service guards and cross-process settings merges. Reuse ProcessFileLock.canonicalURL for newly created paths under aliased ancestors. [Validation](../doc/validation/multiple-instances/README.md).

- 2026-10-23 — [#202](https://github.com/PinedaTec-EU/LeonardoMD/issues/202): coordinate normal termination of all app instances before
  Sparkle installation, retain document/Git safety checks and exclude new
  launches during coordination. Selectively identify Preferences sheets rather
  than ending arbitrary modal decisions. Hosted update/relaunch remains pending.

## 2026-10-29 — Optional document engines

Added opt-in Vega-Lite charts, Citation.js APA references and Markdown extras
(footnotes/callouts), with global/project preferences, lazy local engine loading,
PDF readiness and a shared preference-merge path. Dependency manifests retain
source/license provenance, including bundled citeproc CPAL source. See
[#277](https://github.com/PinedaTec-EU/LeonardoMD/issues/277) and
[extension contract](document-extensions.md).

- Evidence compilation validation ([#282](https://github.com/PinedaTec-EU/LeonardoMD/issues/282)): canonical author declarations are generated from committed HEAD and compared with the PR ledger on PR/comment events; trusted default-branch automation reads candidate data only. See `scripts/evidence_compilation.py` and `doc/release-version-ledger.md`.

- 2026-10-30: Association setup now checks/configures Markdown plus MDLF, MDLR and MDLZ with exact UTI validation and no parent-type fallback. The prompt and General preferences describe all five extensions. Native Finder acceptance remains separate from automated coverage. Tracking: [#293](https://github.com/PinedaTec-EU/LeonardoMD/issues/293).

- Native acceptance for [#293](https://github.com/PinedaTec-EU/LeonardoMD/issues/293) reproduced Finder rejecting MDLZ: `public.archive` alone is a functional UTI without `public.data` conformance. MDLZ now inherits `public.zip-archive` and `public.content`; the declaration regression checks physical file and content conformance for every supported extension.

- 2026-10-30: Remove workspace grouping UI/session lifecycle and add project-context new-tab navigation; legacy stored metadata and package/sync work directories remain intact. [#305](https://github.com/PinedaTec-EU/LeonardoMD/issues/305).

- 2026-11-03 — [#314](https://github.com/PinedaTec-EU/LeonardoMD/issues/314): explorer selection is independent of automatic following, compares display-file identity (original MDLZ for packages), and uses system selection colors. Leonardo filename tint adapts to light/dark appearance. Guide revision 6 documents the distinction.

- 2026-11-05: Corrected sync helper lifecycle diagnostics and listener health recovery in PR #320, tracking [#331](https://github.com/PinedaTec-EU/LeonardoMD/issues/331) and [#332](https://github.com/PinedaTec-EU/LeonardoMD/issues/332). Full suite: 624 XCTest (34 optional skips), 28 Swift Testing cases; focused real TLS and lifecycle regressions pass.

- 2026-11-05: Combined help integration for PR #320 preserves #330, advances main help to v10, and resolves [#333](https://github.com/PinedaTec-EU/LeonardoMD/issues/333) without changing renderer limits or original captures. Full suite: 625 XCTest (34 optional skips), 28 Swift Testing; 56 script cases (7 skips) and all five native guide tests pass. Four successful review compilations were reconciled into the PR ledger rather than discarded.

- 2026-11-05: [#337](https://github.com/PinedaTec-EU/LeonardoMD/issues/337) reorganizes Synchronization by sharing/connecting roles with one common service control; updates bilingual help and captures. PR integration, beta publication and acceptance remain tracked on the issue.
- 2026-11-05: [#202](https://github.com/PinedaTec-EU/LeonardoMD/issues/202), [PR #336](https://github.com/PinedaTec-EU/LeonardoMD/pull/336): Preferences is dismissed before initial and retry Sparkle termination. Final signed/notarized local backport trials update 797→826 and reopen automatically, including Cancel→Save→retry with retained text; owner application unchanged. See [native acceptance](../doc/validation/update-preferences/README.md). Current-head CI and independent judgment remain required; no integration or release claimed.

- 2026-11-05: [#340](https://github.com/PinedaTec-EU/LeonardoMD/issues/340), [PR #344](https://github.com/PinedaTec-EU/LeonardoMD/pull/344): recorded protocol foundations for targeted authenticated rubric requests, explicit capability negotiation, bounded durable retry/expiry/revocation rules and validation limits. Production enrollment remains capability-empty until [#342](https://github.com/PinedaTec-EU/LeonardoMD/issues/342) supplies request/draw/send UI and wiring; user-visible screens and TestFlight remain separate follow-ups in [#341](https://github.com/PinedaTec-EU/LeonardoMD/issues/341)–[#343](https://github.com/PinedaTec-EU/LeonardoMD/issues/343). See [protocol contract](../doc/mobile/rubric-exchange.md).

- 2026-11-05: Reconciled PR #344 compilation evidence after the staged-scope corrections: the post-`5be16ab` focused `swift test --filter 'RubricExchangeTests|HTTPSRuntimeTests.testRubricRequestAcceptAndResponseOverRealHTTPS'` completed successfully (9 exchange tests plus 1 real TLS test, zero failures), followed by one successful full `swift test` (zero failures; opt-in/native tests skipped by configuration). The two already-observed compiler-bearing invocations advance the PR entry build delta from 5 to 7; no command was rerun solely to allocate this correction.

- 2026-11-05: [#341](https://github.com/PinedaTec-EU/LeonardoMD/issues/341), [PR #349](https://github.com/PinedaTec-EU/LeonardoMD/pull/349): macOS now routes targeted rubric capture through the helper/XPC boundary, persists a stable request intent and returned response, offers explicit review/save/insert actions, and guards insertion against document identity changes. The local library carries the request UUID for idempotent retry. The Mac UI intentionally filters to persisted `rubricExchangeV1` peers; current mobile enrollment remains capability-empty until #342. Focused `RubricCaptureTests` covers restart persistence, library deduplication, and delayed lifecycle reply monotonicity. Native visual captures and full packaged help validation remain delivery gates.

- 2026-11-05: [#341](https://github.com/PinedaTec-EU/LeonardoMD/issues/341) delivery evidence completed: bilingual Guide v14 packages pass deterministic packaging and native `BundledUserGuideTests` (5 tests), while `RubricGuideCaptureTests` records production-component request-pending and response-review/save states in English and Spanish under `doc/validation/rubric-capture-341/`. Captures are synthetic native views; no physical iOS or TestFlight acceptance is claimed. The companion remains capability-empty until [#342](https://github.com/PinedaTec-EU/LeonardoMD/issues/342).
- 2026-11-05: [#350](https://github.com/PinedaTec-EU/LeonardoMD/issues/350) recovery correction: the Mac persists a stable rubric intent before the helper create call, keeps it visible when create and status replies are unavailable, and retries the same UUID without changing the original source digest. The authority accepts an identical stable-ID create retry idempotently; focused capture/exchange tests pass at recorded deltas 17–18 and the full current suite passes at delta 20. Guide v14 preserves the synchronized role pages from #337 and adds the same-UUID retry explanation.
- 2026-11-05: Refreshed #341 request/review evidence from final source `6f27d2b66d22da0cc6006317b3039e7a11a1d726`: four synthetic native captures now use the full 760-point editor view in both locales, with metadata fingerprints and source mapping; delta 21 capture test passed. No physical iOS or TestFlight claim is made.
- 2026-11-05: [#350](https://github.com/PinedaTec-EU/LeonardoMD/issues/350) clock correction: #341's capture store and controller now receive one `@Sendable` clock. Record constructors require explicit timestamps; fixed-time tests cover 30-day retention, save ordering, clock rollback and terminal-state monotonicity. Focused `RubricCaptureTests` passes at delta 22.
- 2026-11-05: [#350](https://github.com/PinedaTec-EU/LeonardoMD/issues/350) lifecycle correction: all persisted terminal outcomes now absorb delayed lifecycle replies, while `savedLibraryEntryID` is merged independently of same-state timestamp arbitration. The focused 7×7 transition matrix plus completed-after-cancel and backward-clock save/reopen regressions pass at delta 24.
- 2026-11-05: Refreshed #341 request/review evidence from final source `508c397f211585c7836d91ac932ffed71269dd59`: four synthetic native captures remain full-height 760-point views in English and Spanish, with current metadata fingerprints; the final full suite passes at delta 25. No physical iOS or TestFlight claim is made.
- 2026-11-05: [#350](https://github.com/PinedaTec-EU/LeonardoMD/issues/350) bounded-acknowledgement correction: cancellation intent is persisted separately from a remote `notFound` tombstone; a late create is compensating-cancelled before review/save, pending cancellation survives reopen, and late completed replies cannot reanimate it. Fifteen focused capture tests pass at delta 32; full `swift test` passes at delta 33 with real TLS coverage. Final native request/review evidence maps to `17cd16d4e0d8a971f34832814aef68b6257dc84f`.
- 2026-11-05: [#350](https://github.com/PinedaTec-EU/LeonardoMD/issues/350) final recovery-selection correction: an unsaved response now outranks a newer cancellation marker for the same document, while a cancellation marker remains visible after reopen and cannot be saved or reanimated. Focused `RubricCaptureTests` passes at delta 34 and final full `swift test` passes at delta 35; evidence maps to `a6d086b0941f645f5f6343a08d048b1fed7cc903`.

- 2026-11-06: [#342](https://github.com/PinedaTec-EU/LeonardoMD/issues/342), draft [PR #352](https://github.com/PinedaTec-EU/LeonardoMD/pull/352): Little Leonardo now advertises the optional capture capability only with a complete handler, refreshes it for already-linked mobile devices without changing grants/kind/credential/cache, and keeps legacy server capability semantics. The iOS request card accepts/rejects explicitly, draws with finger/Pencil, supports undo/clear/preview, restores unsent label/drawing after restart, freezes a 24 KiB response before Send and retries exact bytes without state regression. Signed iPhone18Pro/iOS27.0 Simulator UI and owned Mac pinned-HTTPS fixture pass the end-to-end response flow; evidence is capture-only and makes no physical/TestFlight claim. Bilingual Guide v15 preserves #337 role pages and adds the response-boundary instructions.
- 2026-11-06: [#342](https://github.com/PinedaTec-EU/LeonardoMD/issues/342), draft [PR #352](https://github.com/PinedaTec-EU/LeonardoMD/pull/352), corrective native evidence at source `44fe550681fa79f10b40a999f49c1a193d0a2184`: the owned iPhone18Pro/iOS27.0 Simulator lost-ack run keeps request polling and replay POSTs gated through termination/relaunch, then reconciles the same request ID; the granted-reader run blocks an accepted unsent drawing after foreground revocation, purges the exact direct cache and preserves unrelated/legacy offline corpora. The three raw drawing/preview/sent exports are hash-mapped in `doc/validation/little-leonardo/ios-rubric-capture-es.json`; full host validation passes 677 XCTest (35 expected skips) plus 70 Swift Testing cases, Guide v15 packaging passes, and no physical/TestFlight/production-network claim is made.
- 2026-11-06: [#359](https://github.com/PinedaTec-EU/LeonardoMD/issues/359) and [#360](https://github.com/PinedaTec-EU/LeonardoMD/issues/360) harden the iOS channel with ordered draft writes, per-connection capture generations, transactional connection snapshots, checked credential retirement and restart reconstruction of pending revocation cleanup. Cache mutations protect current owners during delayed responses, reconnect and retry. [#361](https://github.com/PinedaTec-EU/LeonardoMD/issues/361) fixes blocked terminal retention and atomic capacity rollover; all 10 focused draft-store tests pass at source `164817c`. Native storage-failure/reconnect evidence is being refreshed in [PR #352](https://github.com/PinedaTec-EU/LeonardoMD/pull/352); integration, physical device and TestFlight remain pending. Earlier native checkpoints above are historical.

- 2026-11-07 — [#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380), [PR #382](https://github.com/PinedaTec-EU/LeonardoMD/pull/382): completed actual packaged Guide23 Help EN/ES in PID15291, producer0055c164, with live examples, Math on/off and practice save/close/reopen. Working copies match bundles; original settings/practices restored, normal quit. Evidence: [manifest](../doc/validation/little-leonardo/https-diagnostic-evidence-20261107-v23.json). Physical large-image cause and new TestFlight delivery remain pending.

- 2026-11-10: [#407](https://github.com/PinedaTec-EU/LeonardoMD/issues/407), [PR #408](https://github.com/PinedaTec-EU/LeonardoMD/pull/408): main on-demand conflicts resolved; ordinary Demo and swipe-plus-button project deletion validated, including received-project deletion after refresh. Guide v36 accepted through actual Help in both locales in fresh authorized QA PID 56776; original practices/settings restored and principal retained. Evidence: `doc/validation/mobile-project-lifecycle/native-v36/instance.json`. Final review/merge delegated to the coordinated icon chat.
