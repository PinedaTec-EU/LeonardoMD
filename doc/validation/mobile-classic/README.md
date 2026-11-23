# Little Leonardo Classic native verification

Tracking: [feature386](https://github.com/PinedaTec-EU/LeonardoMD/issues/386), [PR387](https://github.com/PinedaTec-EU/LeonardoMD/pull/387), [title389](https://github.com/PinedaTec-EU/LeonardoMD/issues/389), [startup393](https://github.com/PinedaTec-EU/LeonardoMD/issues/393).

## Current product and scope

Current iOS product/build checkpoint **99cdd46d74f2a34d698a2e158104a9f2e129c7d4** incorporates accepted main00fdf938 (0.3.1082), preserving math377/demo383/diagnostics382. The final follow-up changes only evidence/wiki/entry387. [626 product/build hashes](startup-fix/tested-source-files.json) bind the current native captures to the reviewed head; verify every hash. Earlier final/ and checkpoint captures retain their real source and are historical for iOS after393.

Current coordinated order is387→385. Cache385 is not copied as an unmerged dependency and will reconcile Classic after acceptance. Physical transport380 remains separate and is not claimed fixed. The owner's helper/pin/grants/corpus and peer simulators remain intact.

## Startup393: directly reproduced and corrected

The earlier candidate awaited all of library.reload before dismissing its startup screen. That includes pending acceptance/submission recovery over the network. The correction exposes the library after actual local demo preparation, then continues the existing reload/recovery. It does not change local authorization barriers, draft persistence, network timeouts, consent or submission rules.

The existing real TLS lost-acceptance fixture now suspends the acceptance response during a cold relaunch. The native regression fails before the correction: [raw log](startup-fix/startup-before-ui.log), [historical native image](startup-fix/startup-before.png), source01aea36. It passes after the correction: [UI1/1,75.384s](startup-fix/startup-after-ui.log), [Mac fixture1/1,94.326s](startup-fix/startup-after-server.log). The test closes the recoverable sheet, reaches the library, opens the actual offline English demo while the response remains suspended, confirms acceptance has not silently completed, then releases the response and completes the same acceptance/drawing/explicit Send. [Source/result mapping](startup-fix/startup-regression.json).

Current native originals: [library during suspended recovery](startup-fix/cold-launch-while-rubric-recovery-is-suspended.png), [usable local demo before response release](startup-fix/offline-demo-available-during-pending-rubric-recovery.png). These are synthetic owned QA cases, not a claim of a production-user capture.

## Current native and suite results

| Contract | Evidence |
|---|---|
| Signed build, current iOS source99cdd46 | [build-for-testing pass](startup-fix/ios-build.log), actual installed canonical-baseline metadata0.3.1082/build1082. |
| iOS units plus both demos and About | [15/15 pass](startup-fix/demo-about-unit-tests.log):12 units and3 UI flows, form save/source/relaunch, settings/help/privacy/licenses/pairing. |
| Rubric rotation | [UI1/1,51.983s](startup-fix/rubric-ui-tests.log), [Mac fixture1/1,63.962s](startup-fix/rubric-server-tests.log): manual mode, full landscape/portrait restore with preserved ink, undo/clear/preview/recovery/explicit Send. |
| Native direct reader | [UI1/1,34.379s](startup-fix/reader-ui-tests.log), [Mac fixture1/1,45.877s](startup-fix/reader-server-tests.log): enroll/read/source/refresh/offline/retry/revocation. |
| Full SwiftPM suite | [Raw log](startup-fix/swift-tests.log), [parsed bundle totals](startup-fix/swift-suite-totals.json):704 XCTest,35 planned skips, zero failures;71 Swift Testing. Seven distinct XCTest executables17+81+23+46+56+115+366, not a366-case aggregate. Subsequent correction changes only the iOS entry, outside the macOS package build; shared production/tests remain unchanged. |
| Installed About | [Actual current original](startup-fix/classic-about-installed-application.png) shows0.3.1082(1082), matching [installed Info.plist/executable hash record](startup-fix/installed-bundle.json). This is development simulator metadata, **not** published Classic/TestFlight1082. |

Own successful compiler delta31. Failed commands and no-build UI runs do not increment it. Earlier SE3/iOS26.5 compact rubric/keyboard/About acceptance remains scoped historical layout evidence; see [history](checkpoint-history.md) and compact/.

## Real packaged bilingual Help remains verified

The startup correction is exclusively in the iOS App entry. [399 identical macOS production/help/build-input files](startup-fix/macos-help-source-equivalence.json) independently bind the existing fresh packaged Help acceptance from11a6ddd to the unchanged macOS application. No new macOS build/launch is asserted. The guides, renderer, native Mac app, assets, build/launch scripts and canonical development version are unchanged. The new fixture and UI test are test-only inputs.

Actual packaged QA process14620, real LeonardoMD executable/resources built through launch.sh --qa, source11a6ddd, identityeu.pinedatec.LeonardoMD.qa.a1949518a425466ab703d4f790d31ee1, display0.3.1082/build1082, macOS27.0.1(26A434). Real Help opened Guide25 EN and ES. Both locales verified Mermaid, charts, local images/tables, inline math, one-line/multiline display equations, Markdown-sensitive underscores/underbraces, radicals/cancellation and tagged box-counting equation(1), Math ON/OFF fallback and literal code examples. Both separate practices were filled with fictional answers, saved, closed and reopened with persisted values. [Actual originals/AX](final/captures.json), [launch log](final/packaged-launch.log), [restoration record](final/help-restoration.json). The app quit normally; original preferences/practices restored with3 hashes verified, both guide copies equal bundled packages.

Guide25 ES/EN already documents startup/local offline availability and the Classic/About/rotation workflows. Correction393 restores that promised availability and changes no help step, caption, workflow or guide resource; no guide revision is rewritten. Historical .png-named Mac originals contain native JPEG data; sidecars correctly declare actual formats, and original bytes remain untouched.

## Captures, design and reproduction

[29 current native originals](startup-fix/captures.json), adjacent context/hash sidecars and [selected reference plus current actual landscape/restored portrait](startup-fix/design-comparison.png). The historical before-fix image has its own explicit source/context. Current iPhone18Pro owned simulator926C886F-52D8-4766-B84D-1A5D8C218080, iOS27.0(24A434), SDK27.1,402×874/874×402 native points at3×. Native APIs, no browser. Synthetic loopback TLS data only. Actual stable full-display landscape captured directly; malformed mid-rotation XCTest geometry is excluded. Originals are not cropped, composited or generated. Only the labeled comparison is scaled. [Scoped design QA](design-qa.md) passed after inspecting current pixels.

Build via `python3 scripts/compile-and-record.py --pr-number 387 -- xcodebuild -project Mobile/LittleLeonardo.xcodeproj -scheme LittleLeonardo -destination 'platform=iOS Simulator,id=926C886F-52D8-4766-B84D-1A5D8C218080' -derivedDataPath /tmp/leonardo-386-derived MARKETING_VERSION=0.3.1082 CURRENT_PROJECT_VERSION=1082 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build-for-testing`.

For startup reproduction create a new owned root with `.qa-fixture-owned` = `LittleLeonardoDirectQA\n`; run MobileDirectAcceptanceFixtureTests/testServeNativeMobileRubricFixture using LEONARDO_MOBILE_RUBRIC_QA_ROOT/PORT and MODE=accept-lost-ack. Wait for ready.json. An owned copy of generated xctestrun gets LEONARDO_DIRECT_RUBRIC_QA=1, LEONARDO_MOBILE_RUBRIC_QA_MODE=accept-lost-ack, LEONARDO_DIRECT_QA_PORT/PHASE_FILE and LEONARDO_MOBILE_RUBRIC_QA_ROOT. Run PairingUITests/testMacRequestedRubricCaptureLostAcceptanceAcknowledgementReconcilesAfterRelaunch with test-without-building. Other rubric modehappy and direct reader fixtures use their existing test flows; reader port46993. Never reset peer or user containers. No test hooks were added to production.

Exact-head CI, fresh strict isolated judge, guarded integration and central materialization remain gates. Final TestFlight publication uses a fresh clean accepted-main publisher archive, Apple validation/upload/processing and existing Owner Internal group assignment/readback. No merge or new upload is claimed here. Source-specific [earlier verification](pre-startup-fix.md) and [older checkpoints](checkpoint-history.md) remain historical.
