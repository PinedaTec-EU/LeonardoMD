# Display-math regression validation

Tracking: [#272](https://github.com/PinedaTec-EU/LeonardoMD/issues/272).

## Current main refresh

Current author-owned full native WKWebView captures are in [main-refresh/](main-refresh/).
They use source `70d5f555a69a192b199f5019363a83244394d7a3` after reconciling `origin/main` at
`0b06971` (including the accepted iOS rubric help), regenerating guide revision 16,
and preserving both math and iOS help changes. Helper-generated sidecars bind
actual PNG dimensions, hashes, observed engine/CSS viewport, time and source.

The actual verified QA package launched as fresh PID 54488, baseline version
0.3.1000. Both guide v16 copies opened through Help. The tagged equation, Math
on/off fallback and practice save/close/reopen were observed; test values and
preferences were restored. Original native accessibility observations and hashes
are retained in `main-refresh/packaged-*.ax.txt` and `native-qa.json`.
CUA currently returns only OS-composited window thumbnails, so readable packaged
window screenshots remain pending; no thumbnail is presented as full visual QA.
The full production WKWebView captures provide the current visual evidence.

Current local full Swift suite and focused seven-case math/help suite pass.
Guide packaging tests: 3 pass. PR 363's compilation counter is 10.

The source mapping script compares these capture/build inputs with the review
head, excluding only this evidence directory, the recorded build count and the
non-packaged revision inventory. Run it with the exact review SHA.

## Known separate defects

Underbrace SVG paths remain absent under [#274](https://github.com/PinedaTec-EU/LeonardoMD/issues/274).
Outline navigation remains under [#364](https://github.com/PinedaTec-EU/LeonardoMD/issues/364).
Both are separate from this parser change and are explicitly owner-authorized
follow-up work after this PR integrates.

## Historical evidence

`original-report.png` is the unmodified partner screenshot relayed on 2026-11-06;
its runtime version, extension state and capture time were unavailable.
Root `math-regression-*` captures came from `ec218f2…`; root `packaged-*` captures
came from `cc71996…`, PID 71769. `adjacent-fix/` captures came from `8061b04…`,
PID 45732. These retain their original context and hashes but are superseded by
`main-refresh/`; none is claimed to match the updated main/guide-v16 product.
The earlier CUA JPEG suffix/dimension errors were corrected without modifying
image bytes. An earlier full all-captures run hit AppKit animation starvation;
full tests without optional captures and focused guide captures pass.
