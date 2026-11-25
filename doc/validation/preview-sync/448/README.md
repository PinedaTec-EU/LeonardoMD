# Preview synchronization recovery acceptance — PR #448

## Scope and source

This report records validation for [issue #447](https://github.com/PinedaTec-EU/LeonardoMD/issues/447) and [PR #448](https://github.com/PinedaTec-EU/LeonardoMD/pull/448). The alert implementation source is commit `0a463909c9f8abdf16e1a74b792f0ee4d7266a41`, originally based on `main` at `8711e44aae3babc5beb914bb6b3e69dfe2715e96` (Guide v74). After the native QA, the PR branch was rebased onto latest `main` at `51ae6a74eb967e1af2dcc90c844e71905d23feb0` (#438). That base update adds only the QA teardown rule in `AGENTS.md` and its `.wiki/current-state.md` note; application sources and Guide v78 packages were unchanged. The QA app was built from candidate source `cef05646f202ecd2b6dc5a94089843c62de6cc00`. The change preserves v74 and integrates the bilingual recovery text in Guide v78. Existing Guide v76 and v77 personal-copy paths are occupied by #369 and #368, respectively.

An ordinary Preview synchronization failure now presents one native action. If closing reaches a failed Preview flush, the recovery alert names the affected document and offers Keep Open for retry or an explicit discard of only the unapplied Preview edits. Any other unsaved document changes still use the regular Save, Discard or Cancel decision. During close preparation, already queued Preview and form messages remain authorized through the final renderer snapshot; the gate then closes before the ordinary save decision. A failed inactive tab is selected before the alert appears and remains visible when the user keeps it open.

The reporter-provided screenshot remains attached to public issue #447. The four captures below are separate implementation evidence from the production AppKit alert builders, rendered by the opt-in XCTest with fictional content.

## Historical native alert captures — source `45b5cd7`

These four captures were generated after the final close-snapshot fix by the opt-in AppKit XCTest, run through `swift test --skip-build --disable-automatic-resolution --filter SessionEditingTests/testCapturePreviewSynchronizationWarningsInBothLanguages`. One test passed with zero failures. The existing test executable came from the full-suite build of the same app/test source tree later committed as `3a399d07ba46516bb02b38a4537e9bc769dea6eb`; the intervening commit `45b5cd7f7a92a86f3f4cd0a745e005c921d71ebd` changed only `.wiki` and validation records, not application or test code. The sidecars record their historical source SHA.

The ordinary warning has one action in English and Spanish. The close warning names `sample.md`, explains that unapplied Preview edits can be retried or discarded, and presents Keep Open and a visually destructive Preview-only discard action. These are native alert components, not full application-window captures.

| State | Capture | Sidecar | Captured (UTC) | AppKit viewport | Image pixels |
| --- | --- | --- | --- | ---: | ---: |
| English, ordinary retry | [PNG](preview-alert-en-retry-45b5cd7.png) | [JSON](preview-alert-en-retry-45b5cd7.png.metadata.json) | 2026-11-15 12:32:19.076934 | 306 × 280 pt | 612 × 560 |
| English, close recovery | [PNG](preview-alert-en-close-45b5cd7.png) | [JSON](preview-alert-en-close-45b5cd7.png.metadata.json) | 2026-11-15 12:32:19.534897 | 306 × 330 pt | 612 × 660 |
| Spanish, ordinary retry | [PNG](preview-alert-es-retry-45b5cd7.png) | [JSON](preview-alert-es-retry-45b5cd7.png.metadata.json) | 2026-11-15 12:32:20.010524 | 306 × 312 pt | 612 × 624 |
| Spanish, close recovery | [PNG](preview-alert-es-close-45b5cd7.png) | [JSON](preview-alert-es-close-45b5cd7.png.metadata.json) | 2026-11-15 12:32:20.507148 | 314 × 362 pt | 628 × 724 |

Each sidecar binds the image hash and pixel dimensions to the observed file-write/capture time, native screen state, synthetic data, AppKit viewport points and source revision. These four images record source `45b5cd7f7a92a86f3f4cd0a745e005c921d71ebd`. The earlier unsuffixed captures are from `0a463909c9f8abdf16e1a74b792f0ee4d7266a41`; their links were used in earlier PR comments. Neither set is exact-head evidence for the refreshed candidate below.

## Earlier packaged Help attempt (Guide v76; superseded)

This is historical evidence from the previous candidate. A fresh strict review later found that `User Guides/v76/{en,es}` already contains older #369 personal copies with different bytes and without this PR's recovery paragraph; v77 is also reserved by #368. The earlier v76 run therefore does not establish that the current candidate opens its own guide copy. It also recorded a Spanish practice-form round trip only, not the required English round trip. The v78 candidate uses a separate QA home and its completed acceptance is recorded below. The initial locked-screen attempt is superseded by the completed run.

`./launch.sh --qa` produced the real app bundle. `scripts/qa-bundle.py --verify-only` passed; `CFBundleExecutable` is `LeonardoMD`, and `otool -L` showed its AppKit, SwiftUI and WebKit dependencies without `XCTest.framework`.

The isolated QA app was relaunched from that verified bundle as a fresh process using `CFFIXED_USER_HOME=/private/tmp/leonardo-448-final-home.Z0nRMl` and `LEONARDO_SOURCE_PR=448`. PID `77330` reached `first_window_shown` and `application_ready`; bundle identifier `eu.pinedatec.LeonardoMD.qa.6617357555e04ec9bcee181c0cc99adf`, bundle `/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-ayyin875/LeonardoMDQA.app`, version `0.3.1602`, build `1602`. The process did not forward to an existing app.

In that same process, I opened both bundled guides through the native Help menu: Help → Leonardo user guide… opened `Guide-v76-en.mdlz`, and after temporarily changing the isolated interface language, Ayuda → Guía de Leonardo… opened `Guide-v76-es.mdlz`. Each Help-opened personal copy matched its bundled resource byte-for-byte:

- English SHA-256: `85d3b5fbbb0669584e9264eed202e1bb233a7702f9b93b3d70e1dd87182a185e`.
- Spanish SHA-256: `2b1423efd816a0e8f9c6ef35d3ac31ef2f864486d78a137d8627658b6d015864`.

Both live guides showed their local cover image, Mermaid diagram, tables and Vega-Lite chart. With Mermaid, Math and Charts enabled, the one-line and multiline display equations, inline math, underscore/underbrace expressions and tagged box-counting equation `(1)` rendered without literal delimiters or KaTeX errors. With Math disabled, the English guide retained formula source literally and code examples remained code; Math was re-enabled afterward. Chapter 10 in both locales explained the retry and Preview-only discard choice.

The Spanish practice form was opened from the guide, saved, closed and reopened from the guide button in the same process. Its fictional answers persisted and Ready to share remained unchecked:

| Locale | Name | Goal | Ready to share |
| --- | --- | --- | --- |
| Spanish | `Prueba v76 final` | `Comprobar la persistencia al cerrar y volver a abrir la guía.` | No |

The isolated app language was restored to English and Math remained enabled. The QA app was quit normally. The guide copies, practice form and preferences stayed under the isolated temporary home; the normal user home was not used. These observations remain as history and are not acceptance for v78.

## Guide v78 bilingual native acceptance — passed (PID 55882)

After the macOS session was unlocked, the existing fresh QA bundle was inspected in PID `55882` (version `0.3.1602`, build `1602`, bundle identifier `eu.pinedatec.LeonardoMD.qa.3197e052ff7746c3bc242afec0c516d2`). It ran from `/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-3r6umng3/LeonardoMDQA.app` with the isolated home `/tmp/leonardo-448-v78-qa-home`. `./launch.sh --qa` and `scripts/qa-bundle.py --verify-only` produced and verified the real `LeonardoMD` executable; `otool -L` showed no `XCTest.framework`. Startup reached `first_window_shown` and `application_ready`; this was a fresh process, not a forwarded launch.

In that same process, both packages opened through the native Help menu and their Help-created personal copies matched the bundled bytes exactly:

| Locale | Help entry | Package | Bundle and opened-copy SHA-256 |
| --- | --- | --- | --- |
| English | Help → Leonardo user guide… | `Guide-v78-en.mdlz` | `02966714f9f77c6a615ba5a1236cb5687089fe02507ed9c9386384a92ebe8c53` |
| Spanish | Ayuda → Guía de Leonardo… | `Guide-v78-es.mdlz` | `2291b2dda56b4c2c88eb08d718529dceea6b7b1cda7ef1b717614582f30f43cc` |

Both live guides showed local imagery, tables, Mermaid, the Vega-Lite chart, inline math, one-line and multiline `$$` display formulas, Markdown-sensitive underscore/underbrace expressions, and the tagged box-counting equation `(1)`. With Math enabled, display equations and the tag rendered in English and Spanish without KaTeX errors or literal delimiters. With Math disabled, the English formula source and code examples stayed literal; Math was re-enabled. Chapter 10's close-recovery guidance was visually checked in both locales.

Both English and Spanish practice forms were filled with synthetic answers, saved, closed and reopened from their guides in PID `55882`. Values persisted and Ready to share remained unchecked. The temporary QA run's seeded v76 guide files and practice files were restored byte-for-byte afterward; final hashes equal their seeded values: v76 English `5e8ae8a5ad6ffb3682e2a0c7f1789531b47efeed2b53b171878a845d3067fc4e`, v76 Spanish `e65f4f77f641cf6fcff2cac9576fba70234a943eb05647f784d71e6748e5af2a`, English form `5b914af748cff65eb9b6bae0b175f64c0008e1874bb1b53fdf6c5a361e0b6b9c`, Spanish form `6b543d197f5195cb1f3906351a2d3b992b0c48e4f7548cf8b164bd92cb7ed487`. The app language was restored to English, Math/Mermaid/Charts remained enabled, and the isolated process quit normally. The task-owned process was PID `55882`, started at `2026-11-15T08:16:08.149980Z`, executable `/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-3r6umng3/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`, with isolated home `/tmp/leonardo-448-v78-qa-home`. Unified macOS logs record normal termination at `2026-11-15T08:25:37.829Z`; a later `ps -p 55882` check at `2026-11-15T09:07:48Z` returned no process row. No Device Hub session or simulator was created by this task. No full-guide screenshots were retained; the four PNGs above remain the alert-component captures.

The machine-readable record in `native-acceptance.json` includes the process, bundle and package hashes, both practice round trips, extension state and restored-file hashes. This Guide v78 acceptance supersedes the initial locked-screen pending note and the separate earlier Guide v76 acceptance; it does not change the scope of the four alert captures.

## Final close-snapshot follow-up — packaged macOS acceptance passed

After the final close-snapshot correction, `./launch.sh --qa` produced a fresh packaged app from the exact source tree later committed as `3a399d07ba46516bb02b38a4537e9bc769dea6eb`. The app ran as a fresh process, PID `92928`, version `0.3.1602` / build `1602`, bundle identifier `eu.pinedatec.LeonardoMD.qa.c4e883eb9842455a94659057993d811c`, from `/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-5301of14/LeonardoMDQA.app`, with isolated home `/tmp/leonardo-448-final-qa-uy01_e8j`. Startup reached `first_window_shown` and `application_ready`; the launch did not forward to another process.

Both Guide v78 locales opened through native Help in this process. The Help-created personal copies matched their bundled resources: English `02966714f9f77c6a615ba5a1236cb5687089fe02507ed9c9386384a92ebe8c53` and Spanish `2291b2dda56b4c2c88eb08d718529dceea6b7b1cda7ef1b717614582f30f43cc`. The Spanish live guide showed its chart, Mermaid diagram, image and table; display math, underbraces/subscripts, radical, arrow, cancellation notation and tagged equation rendered with no KaTeX error. With Math disabled, its formula delimiters and source notation remained literal; Math was enabled again afterward. The earlier bilingual v78 inspection above remains the full representative rendering matrix.

English and Spanish practice forms were filled with synthetic answers, saved, closed and reopened from their guides in PID `92928`; values persisted and Ready to share stayed unchecked. The isolated app quit normally and PID `92928` was verified absent. The pre-existing user app PID `72552` remained running throughout. The current QA bundle passed `scripts/qa-bundle.py --verify-only`; `CFBundleExecutable` is `LeonardoMD`, and `otool -L` showed AppKit, SwiftUI and WebKit with no `XCTest.framework`. No full-guide screenshots were retained; the four implementation-owned alert captures above remain the visual evidence.

This follow-up validates the final renderer snapshot changes against the same packaged Guide v78. It supersedes earlier statements that fresh packaged Help acceptance was pending; it does not replace the historical Guide v78 evidence from PID `55882`.

## Automated validation

- Full `scripts/compile-and-record.py --pr-number 448 -- swift test --disable-automatic-resolution` passed at source `0a463909c9f8abdf16e1a74b792f0ee4d7266a41`: 530 XCTest (36 skipped), 44 Swift Testing and 28 package tests; zero failures. Recorded build delta: 22.
- After the close-snapshot correction, the full `scripts/compile-and-record.py --pr-number 448 -- swift test --disable-automatic-resolution` suite passed on the exact source tree committed as `3a399d07ba46516bb02b38a4537e9bc769dea6eb`; recorded build delta: 34. The packaged QA app build passed at delta 36, and its bundle inspection passed as recorded above.
- Focused `SessionEditingTests` and `InlineFormTests` passed: 18 executed, 2 optional capture cases skipped, zero failures. Recorded build delta: 20.
- `LEONARDO_PREVIEW_ALERT_EVIDENCE=doc/validation/preview-sync/448 python3 scripts/compile-and-record.py --pr-number 448 -- swift test --disable-automatic-resolution --filter SessionEditingTests/testCapturePreviewSynchronizationWarningsInBothLanguages` passed: 1 executed, zero failures. Recorded build delta: 21.
- `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py' -v` passed all 3 deterministic Guide packaging checks.
- The full compile produced non-failing warnings in unrelated existing code, including a `.wifiAware` exhaustiveness warning in `Sources/LeonardoSyncTransport/HTTPSResponseDiagnostics.swift`; none is in this PR's source changes.
- Exact-head GitHub CI and a strict independent review are separate merge gates; both require a result for the published PR head.

The four sidecars and this report are linked from the [PR #448 validation thread](https://github.com/PinedaTec-EU/LeonardoMD/pull/448). The [machine-readable record](native-acceptance.json) separates the historical pre-integration candidate from the merged Beta acceptance.


## Merged Beta acceptance — 2026-11-17

PR [#448](https://github.com/PinedaTec-EU/LeonardoMD/pull/448) merged as `76740ee0f0017609978557241115a81872d2ad71`. The Beta tag points to `63ec49278932ec558dd436ed3aa38e7b72d89ce2`. Signed and notarized Beta [v0.3.1884](https://github.com/PinedaTec-EU/LeonardoMD/releases/tag/v0.3.1884) contains Guide v93 and the Preview close recovery. Exact-head [pull_request CI](https://github.com/PinedaTec-EU/LeonardoMD/actions/runs/44099382827), retried [push CI](https://github.com/PinedaTec-EU/LeonardoMD/actions/runs/44099367411), [validation](https://github.com/PinedaTec-EU/LeonardoMD/actions/runs/44120116858) and [evidence-count check](https://github.com/PinedaTec-EU/LeonardoMD/runs/134169597849) passed. The native captures bound to `8f93584b5d6f5ed8e5ef121959539bd7c6a72102` show one Retry action and the close choices Keep Open / Discard Preview Changes.

### Failure and recovery behavior

- `SessionEditingTests.testClosingAfterRendererFailureDiscardsWithoutRetryingFlush` forces the WebKit source snapshot to fail, verifies that the renderer flush returns false, then closes the document. It checks that one close recovery sheet appears; choosing Preview-only discard does not retry the failing flush, closes the tab, and still saves the separate native source draft through the ordinary save decision.
- `SessionEditingTests.testFailedInactiveTabRecoverySelectsAndNamesItsDocument` checks Keep Open and discard for a failed inactive tab, including selection of the affected document behind the sheet and preservation of another tab's draft.
- `SessionEditingTests.testTabWindowAndAppCloseDrainOrRecoverTableResizeAcrossMessageBarriers` covers tab, window and application close preparation while renderer messages arrive around the snapshot barrier. The window delegate and application termination delegate both route through `DocumentTabs.prepareClose`; the failure-resolution method used by that path is the same one exercised above.

These deterministic XCTest/WebKit checks exercise the failure and close decisions in source. The specific rejection was not injected into the separately packaged Beta process; the user's original trigger remains unknown. The packaged app was exercised for release/update and bilingual Help acceptance, and CI verifies the native alert components and close-resolution regressions.

### Packaged Beta Help acceptance

The isolated QA bundle was `/Users/jmr.pineda/Applications/LeonardoMD-QA-448/LeonardoMD.app`, bundle ID `eu.pinedatec.LeonardoMD`, version/build `0.3.1884 / 1884`. It updated from `0.3.1602` through the in-app updater to Beta `0.3.1884`. In one fresh process, PID `47502` (started 2026-11-17 17:21:49 local time), English and Spanish Guide v93 opened through the native Help menu. The contemporaneous QA note records English Mermaid, math, chart, local-image and table examples, plus its practice-form round trip. For Spanish, it records Mermaid, inline/display math, underbraces/subscripts, the tagged box-counting equation `(1)`, chart, local images and tables; Math-disabled fallback preserved literal TeX, and Math was re-enabled. Its practice form also round-tripped. The note reports no visible KaTeX error and records the final extension state as Mermaid, Math, Vega-Lite and Markdown extras on; Citations off, with app language restored to English.

The report did not enumerate the one-line and multiline `$$` cases, Markdown-sensitive TeX, tagged equation, Math-disabled fallback, and literal code examples separately for both locales. Those specific results are therefore not claimed as a complete v93 Help matrix here. A later Help-source identity check compared the current Help-created personal-copy files with the Beta bundle resources:

| Locale | Beta bundled resource SHA-256 | Help-created personal-copy SHA-256 | Identity |
| --- | --- | --- | --- |
| English | `619699672c50a5295b7f6a968f9952a86b9d4f2cfd0389c322e4ec081e9a494c` | `619699672c50a5295b7f6a968f9952a86b9d4f2cfd0389c322e4ec081e9a494c` | Match |
| Spanish | `ea512ab338ad8f269fdd650f29d8520e0a8378baa96309f2151abf1b79a9e519` | `ea512ab338ad8f269fdd650f29d8520e0a8378baa96309f2151abf1b79a9e519` | Match |

Resource files were read from `LeonardoMD-QA-448/LeonardoMD.app/Contents/Resources/LeonardoMD_LeonardoApp.bundle/Contents/Resources/`; the persistent Help copies were read from `~/Library/Application Support/LeonardoMD/User Guides/v93/{en,es}/`. This follow-up verified byte identity without opening, modifying, or replacing the saved copies. It did not repeat the visual smoke: the Mac was locked when this correction was prepared.

PID `47502` received a normal ⌘Q and was confirmed absent afterward. No force quit was used. The original reporter screenshot remains attached to #447. The recorded v93 Help/practice observations and the later byte-identity check are documented above; they do not establish every required formula/fallback result for both locales, and no fresh screenshot of the Beta app in the injected failure state was produced.

### Issue closure chronology

- On 2026-11-17, PR #448 merged as `76740ee0f0017609978557241115a81872d2ad71`. Exact-head CI, validation and evidence-count checks passed, and signed Beta `0.3.1884` supplied the recorded Help and practice-form acceptance.
- On 2026-11-18, installed Beta follow-up PID `6590` at `/Applications/LeonardoMD.app/Contents/MacOS/LeonardoMD` opened Guide v93 in Spanish, rendered the underbrace, radical/long arrow, tagged box-counting equation `(1)` and chart without visible KaTeX errors, restored English, quit normally and was verified absent.
- At 2026-11-18 13:44:56 UTC, the owner recorded the integrated regression and Beta evidence in the [closure comment](https://github.com/PinedaTec-EU/LeonardoMD/issues/447#issuecomment-6980390079). The issue closed at 13:45:04 UTC. The comment explicitly records that the original failed renderer flush was not re-triggered manually in Beta and that closure relies on the deterministic regression coverage and owner-requested Beta acceptance.

### Acceptance decision

The deterministic renderer-failure regression exercises the source-level recovery, Preview-only discard, preservation of other unsaved edits and one-time alert behavior. Exact-head CI for merged #448 passes, and signed Beta `0.3.1884` supplied the recorded Help, practice-form and follow-up rendering observations. The original renderer rejection was not injected into the packaged Beta and its trigger remains unknown. Issue #447 is closed on the integrated regression evidence and owner-requested Beta acceptance, with that limitation preserved in the [closure comment](https://github.com/PinedaTec-EU/LeonardoMD/issues/447#issuecomment-6980390079).
