# Little Leonardo Classic native verification

Tracking: [#386](https://github.com/PinedaTec-EU/LeonardoMD/issues/386), [draft PR #387](https://github.com/PinedaTec-EU/LeonardoMD/pull/387).

## Application identity and source mapping

- Product code checkpoint: `793166b2d9137993fbd6a1313ac18fb5ffe75155`. `tested-source-files.json` binds the tested mobile/renderer Swift files, project and storyboard to this tree. The native binary was compiled from the same source contents before that checkpoint commit was created. No mobile/renderer Swift change follows those captures.
- The later AccentColor asset change aligns the fallback with the already-enforced oxide tint; the original captures retain their actual checkpoint rather than pretending to be fresh captures of the later asset build. The post-change signed build and About/help smoke pass separately. Later guide, image-count-test, ledger and evidence changes do not change the captured mobile drawing code.
- Bundle: `eu.pinedatec.LittleLeonardo`, Debug, simulator ad hoc signing. Debug builds without marketing/build plist values display “Desarrollo”; distribution builds read actual installed metadata. No invented TestFlight version is attributed to this QA bundle.
- Owned simulator: `926C886F-52D8-4766-B84D-1A5D8C218080`, LittleLeonardo386 Classic Rotation QA, iPhone 18 Pro, iOS 27.0 `24A434`, SDK 27.1. Portrait 402×874 / landscape 874×402 native points, captures at 3×.
- Synthetic Mac TLS fixtures with generated credentials and loopback-only services. No personal projects, physical device, App Store/TestFlight or production-network acceptance claim.
- Sidecars use the shared capture schema: `viewport_css` contains native points and the browser fields explicitly identify native SwiftUI/UIKit, not a browser. Capture timestamps come from XCTest attachments or the direct capture file write time; collection time is separate.

## Native results

- `PairingUITests/testClassicLibrarySettingsAndInstalledAbout` and `testMacRequestedRubricCaptureDrawsRestoresAndSendsOverPinnedHTTPS`: **2/2 passed**, `/tmp/leonardo-386-rotation6.xcresult`. Matching service test **1/1 passed**, 84.204 seconds, `/tmp/leonardo-386-service6.log`.
- Rotation acceptance verifies manual expansion/collapse, unchanged portable stroke count on rotate, full-window landscape without Send/label controls, additional landscape drawing, restored portrait ink, Undo/Clear/Preview, unsent-draft recovery after relaunch and explicit Send confirmed by the Mac. `synthetic-rubric-response.json` is the exact synthetic response retained by that fixture.
- `testNativeDirectEnrollmentRefreshOfflineRetentionRetryAndRevocation`: **1/1 passed**, `/tmp/leonardo-386-reader-final.xcresult`; matching service **1/1 passed**, 39.950 seconds. Captures cover enrolled library, project, Markdown, source and confirmed revocation. Read-only and offline/retry behavior are asserted by the real client/server flow.
- Originals are retained alongside context and hash metadata. `rubric-landscape.png` and `rubric-restored.png` are full-display `simctl io screenshot` captures. XCTest app screenshots taken mid-rotation can have stale portrait bounds; those malformed captures are excluded. The full-display captures are not reconstructed or image-generated.

## Local checks

- Recorded iOS build-for-testing passes with ad hoc signing, including the static branded LaunchScreen, asset catalog, actual app executable, bundled license and normal test runners.
- Whole Swift-suite checkpoint: 693 XCTest cases (35 explicit skips) and 70 Swift Testing cases passed. Subsequent changed contracts are covered by 17 MarkdownRenderTests, 5 BundledUserGuideTests, 3 deterministic package-guide tests and the mobile MIT resource mirror test.
- The illustrated Guide v23 native WKWebView test passes both locales, every packaged image, Mermaid, KaTeX display equations and tag, chart and the separate practice link. Component tests supplement, and do not replace, the real packaged Help smoke.
- Guide image-count expectations were advanced for the new real landscape thumbnail. Existing earlier guide copies are explicitly preserved by tests; v23 remains this PR’s unpublished checkpoint.

## Reproduction

Build with `python3 scripts/compile-and-record.py --pr-number 387 -- xcodebuild -project Mobile/LittleLeonardo.xcodeproj -scheme LittleLeonardo -destination 'platform=iOS Simulator,id=926C886F-52D8-4766-B84D-1A5D8C218080' -derivedDataPath /tmp/leonardo-386-derived CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build-for-testing`.

The native network tests are opt-in. Use the existing `MobileDirectAcceptanceFixtureTests` with a new explicitly owned root containing `.qa-fixture-owned` = `LittleLeonardoDirectQA\n`; wait for its ready.json before starting the UI test. Inject the fixture root/phase file/port into a copy of the built xctestrun, not into product code. Use a fresh synthetic app container on this owned simulator so an earlier draft cannot open over pairing. The rubric fixture uses LEONARDO_MOBILE_RUBRIC_QA_ROOT/PORT; UI uses LEONARDO_DIRECT_RUBRIC_QA=1, LEONARDO_DIRECT_QA_PORT and LEONARDO_DIRECT_QA_PHASE_FILE. The direct reader fixture uses LEONARDO_MOBILE_DIRECT_QA_ROOT and port 46993; UI uses LEONARDO_DIRECT_QA=1 and the matching phase file/port. Never reset another simulator or a physical user app.

## Remaining delivery gates

PRs #377 → #383 → #385 → #387 retain their coordinated integration order. This work does not merge the unaccepted demo/cache branches. After those changes reach main, preserve their demo/catalogue/download/cache controls, apply Classic at their presentation boundary and regenerate the guide with revision **25 or later** after checking the integrated base (v23 is historical; #383 reserves v22 and #385 v24).

The mandatory Spanish/English real Help workflow, live supported examples, Math-enabled/disabled fallback and practice open/fill/save/reopen in a fresh tested packaged instance remain **pending**. Other chats own the packaged GUI turn and the running owner app is preserved. The iOS offline FAQ is not presented as that full bundled-guide acceptance. No strict judge PASS, merge, release or TestFlight publication is claimed.

The checkout and owned caches remain active for that refresh/QA: `.worktrees/386-little-classic`, `/tmp/leonardo-386-derived`, `/tmp/leonardo-386-swift` (15 GiB aggregate budget, currently below it). No other chat’s worktree/cache or simulator was removed.

## Reusable QA note

Consolidate with the existing capture-metadata workflow: wait for the actual orientation and native controls, retain a full-display original and its geometry, and inspect the pixels before using rotated XCTest attachments. This prevents the cropped/black transient capture observed during this task from being mistaken for product layout evidence.

## Merge/publication preflight continuation (2026-11-06)

The owner explicitly requested self-approval/merge of PR387 and a new Little Leonardo publication. Read-only App Store Connect preflight confirms app6831533791, bundle eu.pinedatec.LittleLeonardo, team AU2Z3P42U7 and the existing Owner Internal group, with exactly one tester matching the account holder. The approved existing profile/certificate and login-keychain signing scope verify; no keychain search list, entitlement or account setting was changed. Distribution will use publisher-archive only after source integration and version materialization, followed by export, Apple validation, upload, processing and owner-group assignment/readback. No upload has occurred in this checkpoint.

Additional signed native regression: iPhone SE3, owned simulator270F8BA7-3B7B-4030-9C71-DEDF4CF5CB90, iOS26.5. The complete rubric protocol test and Mac fixture pass (114.593s), including opening the portrait label keyboard, verifying that it does not activate the landscape canvas, dismissing it, manual expansion, both rotations, recovery and Send. Local result: /tmp/ll387-compact-before.xcresult; the name describes a preflight run, not a reproduced product defect. No extra orientation observer or speculative product change was needed.

The common Mac GUI is currently locked according to the coordinating publication chat; the required packaged Help acceptance cannot be executed until the owner unlocks it. Other chats retain their existing integration/GUI turns. The read-only release-cleanup script also encounters an already-tracked missing worktree registration; recurrence is recorded in [ai-skills-shared issue22](https://github.com/PinedaTec-EU/ai-skills-shared/issues/22). The selected source/branch/Apple target audit was completed manually without deleting other worktrees.

## Accepted-main reconciliation

The PR branch now incorporates accepted math/outline main0.3.1045 (843670bcd3d5548242f04f11226e06487b3e790b), without advancing main or replacing its renderer changes. Version-only guide conflicts were resolved by regenerating Guide v25 from the combined bilingual bodies, retaining the math/outline additions and Classic rotation instructions. Prior bundled v20/v23 templates are replaced in this branch; their Git history and user-owned working copies remain preserved. Deterministic guide packaging passes. The existing native captures remain checkpoint evidence; exact-head visual acceptance must be refreshed after final demo/cache reconciliation.

### Signed distribution preparation

The author-only Release archive from source `05036373d28d39978d37054237bee48f9a318de7` passed the repository distribution helper, including signing, profile, bundle/resource and provenance checks. The successful compiler-bearing archive raises PR387's ledger delta to20. Private archive and frozen provenance are retained outside the repository at `~/Library/Application Support/PinedaTec/LittleLeonardo-Distribution/pr387-author-0503637/`; command output is `/tmp/ll387-author-archive.log`. This author artifact has not been exported or uploaded and is not the eventual publisher artifact. After integration and central materialization, publication must build the exact clean accepted main checkpoint.

The Mac unlock, final packaged bilingual Help workflow, reconciliation with accepted demo/cache changes, exact-head UI captures, CI and strict isolated judge remain pending. No merge, TestFlight delivery or physical-device acceptance is claimed.
