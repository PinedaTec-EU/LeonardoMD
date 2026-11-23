# Integrated-fixes validation — PR #383

The candidate includes #377 (`d4ca398e85f949c83d623bdf3b2bee0bacb94909`), which closes #274 and #364, and its materialized baseline 0.3.1045. Both bundled guides use revision 22; earlier personal copies remain intact.

## iOS application

Real `LittleLeonardo.app` built from `68b077e47beb3cc5aecb4d901db264a9ac0e280f`; iPhone 17 Pro simulator, iOS 27.0 (24A434), task-owned device `D1B54EA2-B8EF-4DB6-8D49-AEFE06FA924E`. [Machine-readable result](ios-test-summary.json): **14 passed, no failures or skips** (12 unit tests and 2 UI tests).

The English walkthrough resets the demo, confirms empty answers, opens field help, fills and saves a fictional name, then terminates/relaunches and verifies persistence. The Spanish walkthrough resets independently, fills/saves, inspects the Leonardo source with separate `values`, returns to preview, edits again, saves and verifies the exact edited value after another relaunch. The test does not assume a particular insertion caret position.

Original XCTest attachments and adjacent native provenance sidecars:

- [English welcome](english-welcome.png), [Spanish welcome](spanish-welcome.png).
- [Markdown and table](english-gallery-0.png), [local image and Mermaid](english-gallery-1.png).
- [Actual inline/display math, underbrace, tag (1), chart](english-gallery-2.png).
- [Form fields](english-gallery-3.png), [saved English practice](english-saved-practice.png).
- [Spanish source](spanish-source-with-saved-values.png), [Spanish persisted practice after source](spanish-persisted-practice-after-source.png).

Manual inspection confirms the image, diagram, underbrace shape, equations/tag, chart and real fields. Native XCTest exposes neither a browser version nor a CSS viewport; metadata records that limitation and actual image dimensions/hashes rather than fabricating browser-only fields. Local Debug distribution version fields are absent; the full source SHA identifies this artifact.

## Other checks

- Refreshed full SwiftPM: **366 XCTest cases, 30 skipped, no failures**, plus **28 Swift Testing cases passed**. Source `28bc6eb`; subsequent product changes consist only of the materialized version/notes baseline. CI revalidates the final head.
- Bundled guide components: **5 passed**. Python tools: **111 cases, 7 skipped**; portable format: **38 passed**; packaging: **20 passed**; deterministic guide generation: **3 passed**. Both demo MDLR resources pass the canonical v1 schema.
- Twelve successful compiler-bearing invocations are allocated in this PR's ledger, including release preparation and the canonical QA launch. The failed caret-assumption test invocation is excluded.

## Fresh packaged macOS acceptance — 7 November 2026

Source `5d19e71c264feb9db8ea146e373996f192ecf473`, baseline version **0.3.1045 / build 1045**, fresh PID **17838**. `LEONARDO_SOURCE_PR=383 ./launch.sh --qa` packaged and launched the real executable, resources and dependencies. `qa-bundle.py --verify-only` and `otool -L` verified packaging and no XCTest GUI linkage. The full native identity, exact bundle identifier/path, template/personal-copy SHA-256 pairs and restoration checks are in [native-identity.json](macos-help/native-identity.json). Both locales matched their candidate bundle byte for byte before counting Help evidence.

Opened English and Spanish from the real Help menu in that same instance. Both passed:

- Actual Mermaid, inline math, one-line display mean, sensitive underbrace/subscript TeX, radical/long arrow/cancellation shape, multiline box-counting equation and tag `(1)`, chart, local image and table. No KaTeX error or literal delimiters in rendered equations; the inline source example remains literal.
- Outline selection lands on its matching Display formulas heading, with image/chart layout above it. [English formula destination](macos-help/en-math-enabled.jpg), [Spanish formula destination](macos-help/es-math-enabled.jpg).
- [English diagram/mean](macos-help/en-diagram-mean.jpg), [Spanish diagram/mean/tagged equation/chart](macos-help/es-diagram-mean.jpg), [English table/local image](macos-help/en-table-image.jpg), [Spanish table/local image](macos-help/es-table-image.jpg).
- Disable Mermaid, Math and Charts in Preferences and decline the recommendation with Not now / Ahora no. The actual [English fallback](macos-help/en-examples-disabled.jpg), [English chart code](macos-help/en-chart-disabled.jpg) and [Spanish fallback](macos-help/es-examples-disabled.jpg) retain authored source/notation. Original engines were restored afterward.
- Open the separate practice through the guide, fill fictional name/goal/checkmark, save, close and reopen through the guide. Both locales retain all three values: [English reopened AX state](macos-help/en-practice-reopened.ax.txt), [Spanish reopened AX state](macos-help/es-practice-reopened.ax.txt) and [Spanish original screenshot](macos-help/es-practice-reopened.jpg). The English practice screenshot was an unusable window thumbnail and is deliberately excluded; persistence is directly recorded by the actual reopened controls' AX values. The English iOS form has its separate full-size captures above.
- Inspect this PR's mobile appendix in both languages: [English instructions](macos-help/en-mobile-instructions.jpg), [Spanish instructions](macos-help/es-mobile-instructions.jpg).

All retained native pictures are original JPEG bytes returned by CUA, with actual dimensions read from their image metadata and adjacent provenance sidecars. Native browser-version/CSS-viewport fields are unavailable and explicitly recorded; these are app-window captures, not browser screenshots. Early window thumbnails were excluded.

The QA process quit normally. No LeonardoMD process remained. Original English interface, Mermaid/Math/Charts enabled, Markdown extras enabled and Citations disabled were restored. Pre-existing practice bytes were retained by moving their directory to a unique backup; after quitting, the QA results were moved aside and originals restored, with every original file hash verified. Guide v22 did not exist beforehand and that original absence was restored. Other guide revisions/helpers/workspaces were untouched. The GUI was released to the coordinated diagnostic thread before CI/review work.

## Source mapping and reproduction

The iOS capture source is `68b077e47beb3cc5aecb4d901db264a9ac0e280f`; the macOS capture source is `5d19e71c264feb9db8ea146e373996f192ecf473`. Subsequent commits add only validation evidence, compact wiki/inventory updates and the compilation ledger. Verify `git diff <capture-source> <reviewed-head> -- Mobile Sources Package.swift scripts/package-user-guide.py doc/guide/en/body.md doc/guide/es/body.md` is empty before reusing captures. Any product/resource change requires new candidate evidence.

For an independent reproduction, use an isolated checkout at the reviewed head. Run the project's compilation recorder with `xcodebuild test -project Mobile/LittleLeonardo.xcodeproj -scheme LittleLeonardo -destination 'platform=iOS Simulator,id=<own-device>' -only-testing:LittleLeonardoTests -only-testing:LittleLeonardoUITests/MobileDemoUITests CODE_SIGNING_ALLOWED=NO`; create a separate simulator and keep derived data outside the checkout. For macOS use `LEONARDO_SOURCE_PR=383 ./launch.sh --qa`, after coordinating exclusive single-instance ownership. In the actual app open Help, choose each interface language in General, inspect the live examples/outline and perform the separate practice save/reopen. Preserve existing copies and verify bundle/copy hashes first. Do not open a second app while another thread owns the GUI. No browser route/live web preview applies to this native scope.

Final exact-head CI and a fresh strict independent judge remain the merge gates; this record reports acceptance, not a published beta or a merged PR.

No App Store/TestFlight upload, physical-device or airplane-mode exercise is claimed. Demo resources are bundled and no pairing/account/network is required; synchronized projects remain read-only and separate from demo storage.
