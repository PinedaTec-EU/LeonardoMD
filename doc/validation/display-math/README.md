# Display-math regression validation

Tracking: [#272](https://github.com/PinedaTec-EU/LeonardoMD/issues/272).

`original-report.png` is the unmodified screenshot relayed by the owner on
2026-11-06 from their partner. Capture time, runtime version, OS, source document
and extension state were not supplied. It proves the reported literal notation,
not which cause produced that particular instance.

The two `math-regression` images are native WKWebView component captures of
both packaged guide locales, with Math, Mermaid and Charts enabled and synthetic
guide content. Their sidecars record source ec218f2b1bf55624cd527b2625e802d14b0cde63,
viewport, engine user agent, OS and capture time. They are not fresh packaged-app
process evidence. Subsequent ledger build-count/evidence-only commits do not
change the captured Swift/JavaScript/content sources.

The tagged box-counting equation renders completely. Underbraces remain absent
because of the separately tracked SVG sanitization defect
[#274](https://github.com/PinedaTec-EU/LeonardoMD/issues/274); these captures are
explicit evidence of that limitation, not a claim that extensible symbols pass.

Validation:
- Full `swift test`: 662 XCTest cases, 34 skipped, zero failures; 70 additional
  Swift Testing cases pass. Run without the optional capture environment.
- Focused native display-math and bilingual guide suite: 6 cases pass, including
  enabled/disabled engine replacement, code exclusion and editing boundaries.
- Script suite: 95 tests pass, 7 skipped by environment/engine conditions.
- Release app builds and passes packaged executable/dependency verification.
- The earlier full run with all optional visual captures was stopped after
  AppKit exhausted dispatch threads in animations and recent-document lookup;
  the full run without captures and targeted guide captures both pass.

Packaged-process Help acceptance is pending: the Mac was locked when computer
control tried to inspect the running application. The owner authorized closing
the installed app for this test; no forced termination or unsaved-data discard
was performed. Resume through `LEONARDO_SOURCE_PR=363 ./launch.sh --qa` after
unlocking, verify a new PID and first window, then open both guides through Help.
