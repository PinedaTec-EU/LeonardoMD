# Graphic inspector validation

Tracks [#323](https://github.com/PinedaTec-EU/LeonardoMD/issues/323) and [#322](https://github.com/PinedaTec-EU/LeonardoMD/issues/322).

## Runtime and provenance

Native captures were taken from runtime source `237d586c37544aab55db4b711b652d391b25269d` through the real app built by `./launch.sh --qa --args --new-instance -allowMultipleInstances YES`. `qa-bundle.json` records bundle identity, executable digest and dependency inspection (no XCTest framework). A first release-notes window and then the synthetic document window were observed. The process identifier/startup log was not retained; the evidence does not claim a PID-based startup audit. Only the disposable QA instance received Quit after the fixture was saved.

`runtime-source-sha256.json` pins runtime files. Subsequent validation/evidence and compilation-ledger commits do not change those files. Each original CUA screenshot has a timestamp, digest and pixel dimensions in its context sidecar. CUA does not expose the native-point viewport here; no CSS/browser viewport is invented for this native window. The 320×850-point production-component guide captures have separately measured view bounds and metadata under `doc/guide/{en,es}/assets/graphic-inspector.*`.

All fixtures and ink are synthetic. The owner's screenshot/signature is not published.

## Native scenarios observed

- Select first rubric → floating X/Y/Z summary and Inspect, no editable controls in the floating bar.
- Inspect → right-hand native inspector with ink preview, page, geometry, linked size and stacking controls.
- Colors → White changes the actual inserted ink and preview; selection remains visible. Undo restores blue; Redo restores white and keeps selection.
- Select second rubric → inspector identity, coordinates, size and blue ink update to that object.
- Select text in the document → both object toolbar/frame and object inspector disappear.
- Save → `after.mdlf` preserves document body and second object exactly; first object's strokes differ only in color. Existing serializer normalizes layout defaults on save. See `persistence.json` and `before.mdlf`.
- Earlier native geometry QA on source `4c559e4` confirmed editing Width retains selection through redraw. The final runtime retains this fix and the WK regression test covers the redraw.

Custom macOS color-panel interaction was not manually verified through CUA; preset recoloring was verified in the native app, and both controls share the same document-scoped recoloring action. Automated tests cover mixed ink, invalid colors, stale selection, save/reopen, undo/redo and unchanged library.

## Visual comparison

Compared the actual `native/inspector-top.jpg` directly with `doc/design/323/selected-inspector.png`: the right-hand identity/ink-preview → geometry → stacking hierarchy is retained, using existing native styling and the current compact header. The additional color section replaces the reference's library-management section; insertion/library remain in Insert as scoped. The panel scrolls at limited window height. `native/inspector-white.jpg` shows lower color controls; `native/text-selection.jpg` shows dismissed object chrome.

## Checks and reproduction

Final local checks on the runtime above:

- `python3 scripts/compile-and-record.py --pr-number 326 -- swift test`: 601 XCTest cases, 32 opt-in skips, zero failures; 70 Swift Testing cases passed.
- `python3 scripts/compile-and-record.py --pr-number 326 -- xcodebuild -project Mobile/LittleLeonardo.xcodeproj -scheme LittleLeonardo -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/little-ios CODE_SIGNING_ALLOWED=NO build`: succeeded.
- `python3 -m unittest scripts.tests.test_package_user_guide`: deterministic bilingual v8 packaging passed. Earlier full Python suites passed: scripts 52 (7 skips), plugin 38, packaging 20.
- Focused `GraphicInspectionTests`, `GraphicSelectionRuntimeTests` and opt-in `RubricGuideCaptureTests` passed after the final native-color action changes.

To reproduce native behavior at the PR head: build with the QA command above, open `doc/validation/graphic-inspector/before.mdlf`, enable structural editing, select a rubric and click Inspect. Use synthetic copies when saving. Close any task-owned QA instance normally; do not terminate another running Leonardo instance.

For production-component instructional captures: `LEONARDO_RUBRIC_GUIDE_CAPTURE=/tmp/leonardo-inspector-captures EVIDENCE_SHA=$(git rev-parse HEAD) python3 scripts/compile-and-record.py --pr-number 326 -- swift test --filter RubricGuideCaptureTests` (read the test for its output directory). Repackage with `python3 scripts/package-user-guide.py --web-output doc`.
