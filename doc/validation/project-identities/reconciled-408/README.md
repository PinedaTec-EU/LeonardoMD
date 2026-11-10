# Reconciliation after #408

Current acceptance record for [#399](https://github.com/PinedaTec-EU/LeonardoMD/issues/399) / [#400](https://github.com/PinedaTec-EU/LeonardoMD/pull/400), after [#408](https://github.com/PinedaTec-EU/LeonardoMD/pull/408) was merged and materialized as `f04564a235343b8efff5316bd95b6416550f291c`.

The previous Guide28 evidence in the parent directory is historical. It does not establish acceptance for this reconciled candidate.

## Preserved behavior

- One sorted iOS project library: Demo is local; directly received projects have the network indicator; legacy recovery archives remain separately described.
- Stable outer open/delete/restore navigation identifiers and swipe-plus-tap deletion, with full-swipe deletion disabled.
- Received catalogue headers retain the on-demand browser, cache/retention controls and compact document reader.
- macOS local/outgoing/received presentation remains independent of connection availability and sharing scope.
- Both Guide42 sources and generated editions explain project origin and independent per-file transfer/offline states.

## Validation completed

| Check | Result |
| --- | --- |
| Focused Swift identity, presentation, guide and capture checks | Passed; see `checks/swift-focused.log.gz`. |
| Full Swift suite | 754 XCTest cases, 40 expected skips, zero failures; 72 Swift Testing cases, zero failures. See `checks/swift-full.log.gz`. |
| Repository Python suite | 118 tests, seven expected skips, zero failures; see `checks/python.log.gz`. |
| Deterministic Guide42 packaging | Three tests passed; packaged image counts EN20/ES21. |
| iOS unit tests | 22/22 passed. |
| Bilingual Demo and project lifecycle UI | 3/3 passed, including the local Demo header, deletion, restoration and retained practice answers. |
| Received project on-demand UI | 1/1 passed against an independent loopback HTTPS source; includes navigation, retention/retry, relaunch and explicit deletion. |
| Installed iOS About/Help UI | 1/1 passed. |
| Independent HTTPS source assertions | 1/1 passed; metadata-only enrollment, one requested file, no eager snapshots, retry and future retained file are verified. |
| Native Mac component captures | Eight current original PNGs across both locales, light/dark, 220/540 native points, plus two compact guide illustrations. |
| Native iOS component captures | Eight current original PNGs across received/recovery roles, iPhone/iPad widths and standard/accessibility Dynamic Type. |
| Packaged macOS inspection | Real `LeonardoMD` executable, valid dependencies/signing, no XCTest dependency; version/build `0.3.1233/1233`. |

The on-demand test selector correction is tracked in [#416](https://github.com/PinedaTec-EU/LeonardoMD/issues/416) and included in `acb46fc23bf883098d9112803b457e23ac2f21c4`. Only this test identifier and compilation accounting differ from the initial reconciliation commit `33650e806efc05cfe462118da3e0b08c44b8f69f`; product inputs are unchanged.

## Pending acceptance

The host was locked when CUA attempted to inspect the real macOS QA application. A fresh candidate PID `86473` exists, but first-window readiness and actual Help42 acceptance have **not** been claimed. Manual host unlock is required. The user has also been asked to authorize temporary language/Math changes with restoration for this smoke test; no preference change has been performed.

After unlock, open both bundled locales through the real Help workflow in the same QA process. Verify bundle/personal-copy content identity, changed project examples, Mermaid, inline and one-line/multiline display math, underbraces and the tagged equation, charts, local images, tables, literal code, disabled-Math fallback and separate practice fill/save/close/reopen. Restore original preferences and practice bytes, quit normally and record the outcome.

The candidate remains draft. Final exact-head CI and a fresh strict independent judge are pending this acceptance; no previous PASS is reused. PR #400 must remain open for the owner to integrate.

## Native capture metadata

Original bytes and test-emitted contexts are preserved. Native sidecars use the shared metadata helper's image/hash and Git-source routines, with `viewport_css: null`; measured native points are recorded separately. A browser engine is not applicable to AppKit/UIKit components. These component fixtures do not prove packaged-process startup or physical-device/network acceptance.

Raw compiler/test logs are preserved byte-for-byte in deterministic gzip archives; `checks/log-archives.json` binds their original and compressed hashes. Decompress with `gzip -dc` to inspect the original diagnostics.
