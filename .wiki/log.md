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

[#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92) defines the iOS companion, direct read-only LAN snapshots and folder-scoped Git editing. The new standalone `LeonardoSync` target provides corpus boundaries, offline state/persistence and safe project snapshot reading. See [mobile contract and pending implementation](../doc/mobile/little-leonardo.md). This does not establish a runnable iOS app or completed synchronization.

Native iOS checkpoint for [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92): shared `LittleLeonardo` Xcode scheme builds for iOS Simulator; a fresh process on iPhone 17 Pro Max loads synthetic cached direct/Git projects. Native local reading and Git-mode offline mutation controls exist; no network/Git synchronization claim. CI includes the iOS build and the ledger scopes `Mobile/**`.
