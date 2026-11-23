# Historical verification before startup correction393

Superseded for iOS by startup-fix/ and the current README. The macOS Help evidence remains applicable through the separately verified unchanged macOS production inputs.

# Little Leonardo Classic native verification

Tracking: [issue386](https://github.com/PinedaTec-EU/LeonardoMD/issues/386), [PR387](https://github.com/PinedaTec-EU/LeonardoMD/pull/387), [title bug389](https://github.com/PinedaTec-EU/LeonardoMD/issues/389).

## Final combined candidate (2026-11-07)

Product/build checkpoint: `11a6ddd537a7c3a014b3e21a7062b6aca4346655`, based on accepted main `00fdf938ebba3d9125461d12267c0e89f60b148e` (0.3.1082). Accepted math377, demo383 and diagnostics382 are preserved. The following evidence-only commit changes documentation, wiki and compilation ledger only; [tested-source-files.json](final/tested-source-files.json) binds all tracked Mobile/Sources/Tests/resources/build scripts to the reviewed tree. Verify every hash against the PR head before using these captures. This mapping follows the shared evidence-only-commit contract; capture source is never relabeled as a later binary.

The latest owner mandate387/TestFlight takes precedence over the earlier optional385-first schedule. Both chats coordinate **387 →385**: the unmerged cache implementation is not copied here and will reconcile Classic from accepted main. Issue386 criterion7 preserves cache when it reaches main; it does not require that separate feature first.

## Final validation

| Contract | Direct evidence |
|---|---|
| Complete Swift suite | [704 XCTest,35 planned skips;71 Swift Testing, all pass](final/swift-tests.log). Source403c7d6; subsequent11a6ddd adds only a UI screenshot attachment, with unchanged production code. |
| Signed iOS build | [Build-for-testing pass](final/ios-build.log), source11a6ddd, iPhone18Pro/iOS27.0(24A434), SDK27.1. |
| Both offline demos and About/settings/pairing | [3/3 native UI pass](final/demo-about-tests.log); forms persist independently across relaunch/source editing. |
| Full rubric flow | [UI1/1](final/rubric-ui-tests.log), [Mac fixture1/1,62.744s](final/rubric-server-tests.log). Manual expansion/collapse, rotate/restore, ink preservation, undo/clear/preview, draft recovery, explicit confirmed Send. |
| Real reader protocol | [UI1/1,33.930s](final/reader-ui-tests.log), [Mac fixture1/1,45.324s](final/reader-server-tests.log). Enrollment, projects, Markdown/source, refresh, offline/retry and confirmed revocation. |
| Compact device | Earlier signed SE3/iOS26.5 rubric and About workflows pass; portrait keyboard does not expand canvas. [Historical source-specific proof](checkpoint-history.md), [compact originals](compact/). |
| Packaged bilingual Help | Fresh real process14620 built through `LEONARDO_SOURCE_PR=387 ./launch.sh --qa`; [launch/build log](final/packaged-launch.log). Real Help menu opened Guide25 EN/ES, then every representative live example and separate practice. |

### Real Help acceptance

Packaged native identity: `eu.pinedatec.LeonardoMD.qa.a1949518a425466ab703d4f790d31ee1`, real LeonardoMD executable/resources/frameworks, source11a6ddd, development QA display0.3.1082/build1082 on macOS27.0.1(26A434). The version is inherited development metadata, **not** a claim that TestFlight1082 contains Classic.

Both locales visibly render Mermaid, charts, local images/tables, inline math, one-line/multiline display equations, Markdown-sensitive underscores/underbraces, radicals/cancellation and the tagged box-counting equation(1), without KaTeX errors or literal delimiters. Code examples remain literal. Math OFF displays the source fallback in both locales; Math ON restores equations. Native original PNGs and AX text are retained under `final/help-*`, including [EN equations](final/help-en-enabled.png), [ES equations](final/help-es-enabled.png), [EN fallback](final/help-en-math-disabled.png), [ES fallback](final/help-es-math-disabled.png).

The guide's own practice links opened separate Fill-mode files. Fictional answers were entered, saved, closed and reopened through each guide, with the actual persisted values visible: [EN](final/help-en-practice-reopened-ready.png), [ES](final/help-es-practice-reopened-ready.png). The test app quit normally. Original preferences and both personal practice files were restored with all3 hashes verified; [restoration record](final/help-restoration.json). Both personal Guide25 copies exactly match bundled originals. Existing helper41636, pin/grants/corpus and peer simulators were preserved.

## Visual evidence and reproduction

[40 native original captures](final/captures.json), context files and hash sidecars retain their actual timestamps, native geometry and source. iPhone18Pro owned simulator926C886F-52D8-4766-B84D-1A5D8C218080 is402×874 portrait /874×402 landscape points at3×. Desktop full-window captures1260×850 native points at2×. Native APIs are explicitly identified instead of inventing a browser version. Synthetic loopback TLS data only; no physical-device or production-network acceptance claim.

[Selected Product Design reference plus actual final landscape/restored portrait](final/design-comparison.png) was inspected together. [Scoped design QA](design-qa.md) passes. Original screenshots are never resized/reconstructed in place. The landscape original comes from the actual stable full-display capture; stale-bounds XCTest rotation capture is excluded. The restored portrait attachment shows both real ink strokes after returning from landscape.

Build with `python3 scripts/compile-and-record.py --pr-number 387 -- xcodebuild -project Mobile/LittleLeonardo.xcodeproj -scheme LittleLeonardo -destination 'platform=iOS Simulator,id=926C886F-52D8-4766-B84D-1A5D8C218080' -derivedDataPath /tmp/leonardo-386-derived CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build-for-testing`.

For interactive native reproduction, launch the built LittleLeonardo.app on an owned simulator. Demo and About require no service. For protocol/rubric tests create a fresh synthetic root containing `.qa-fixture-owned` = `LittleLeonardoDirectQA\n`, run the existing `MobileDirectAcceptanceFixtureTests` with `swift test --skip-build --scratch-path /tmp/leonardo-386-swift --filter MobileDirectAcceptanceFixtureTests/testServeNativeMobileRubricFixture` and LEONARDO_MOBILE_RUBRIC_QA_ROOT/PORT. Wait for ready.json. Inject LEONARDO_DIRECT_RUBRIC_QA=1, LEONARDO_DIRECT_QA_PORT and LEONARDO_DIRECT_QA_PHASE_FILE into an owned copy of the generated xctestrun. Use test-without-building for PairingUITests/testMacRequestedRubricCaptureDrawsRestoresAndSendsOverPinnedHTTPS. Direct reader instead uses testServeNativeMobileAcceptanceFixture, LEONARDO_MOBILE_DIRECT_QA_ROOT, port46993 and UI LEONARDO_DIRECT_QA=1. Never reset peer devices or real user containers. Native app, not a web preview.

## Delivery boundaries

Own successful compiler count28 is recorded in entry387. Required exact-head CI and strict fresh judge remain merge gates. Final TestFlight publication requires accepted main, central ledger materialization, a fresh clean publisher archive, export/Apple validation, upload, processing and assignment/readback of the existing Owner Internal group. No earlier author archive or diagnostic1082 is substituted. At this evidence checkpoint no merge/upload is claimed.

Physical-device transport issue380 remains separately investigated; Classic does not claim to fix it. No security/authorization policy is relaxed. Read-only documents, accepted rubric consent and explicit Send remain authoritative. Shared release-cleanup's stale unrelated worktree registration is already tracked in ai-skills-shared issue22; no peer worktree is pruned. Owned caches remain within15GiB. [Earlier checkpoints](checkpoint-history.md) retain their actual historical limitations.

## Complete-suite accounting

SwiftPM runs seven XCTest executables. The last366-test summary belongs to LeonardoAppTests only; it is not the aggregate. Count each `.xctest` summary once, excluding repeated nested/All tests summaries. [Machine-readable totals](final/swift-suite-totals.json) are parsed from the unchanged durable log.

| XCTest executable | Tests | Skipped | Log line |
|---|---:|---:|---:|
| LeonardoSyncTransportTests.xctest | 17 | 0 | [167](final/swift-tests.log#L167) |
| LeonardoSyncTests.xctest | 81 | 0 | [390](final/swift-tests.log#L390) |
| LeonardoRenderTests.xctest | 23 | 1 | [467](final/swift-tests.log#L467) |
| LeonardoIntegrationTests.xctest | 46 | 0 | [580](final/swift-tests.log#L580) |
| LeonardoDesktopSyncTests.xctest | 56 | 4 | [754](final/swift-tests.log#L754) |
| LeonardoCoreTests.xctest | 115 | 0 | [1044](final/swift-tests.log#L1044) |
| LeonardoAppTests.xctest | 366 | 30 | [2038](final/swift-tests.log#L2038) |
| **Total** | **704** | **35** | Zero failures |

Swift Testing separately reports43+28=71 passing tests. No suite was rerun or counted twice to produce this total.

## Installed About metadata acceptance

An additional signed Release build-for-testing from product-equivalent source `a7f58b6a076855fa8cc7a2486b136891e4e88139` supplies the canonical baseline metadata through `MARKETING_VERSION=0.3.1082 CURRENT_PROJECT_VERSION=1082`. The actual installed Info.plist and executable are hashed in [installed-bundle.json](final/versioned-about/installed-bundle.json). The real About workflow passes1/1(24.948s), and the [original installed About capture](final/versioned-about/about-installed-version.png) visibly reads **0.3.1082(1082)**. The original has context/hash metadata; [build log](final/versioned-about/release-build.log), [UI log](final/versioned-about/about-ui-test.log). Testability is enabled solely for this Release simulator test configuration; no product source or canonical version file is changed. The initial unsupported Release unit-test invocation lacked testability and failed before any recorder increment; the corrected invocation records delta28. The final distribution remains a fresh publisher archive without tests.

The earlier Debug About original truthfully retains Desarrollo because its generated plist omitted version fields. It is superseded for installed-version acceptance by this metadata-populated Release capture. The value1082 is development acceptance metadata, not a claim that published TestFlight1082 contains Classic. Final TestFlight version is assigned only after source integration/materialization. All626 product/build hashes remain identical across11a6ddd, a7f58b6 and this evidence-only follow-up.
