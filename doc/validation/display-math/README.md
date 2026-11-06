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

Packaged-process Help acceptance completed after the owner unlocked the Mac and
authorized closing the installed app. It quit normally; `./launch.sh --qa` started
PID 71769 from the verified real executable and dependencies. The fresh window,
Help → guide actions and revision-15 personal-copy paths were observed in both
locales. `packaged-en.png` and `packaged-es.png` show the equations in that process;
sidecars identify the bundle and unmaterialized baseline version 0.3.898.

Observed Math enabled rendering and disabled literal fallback (English), restored
Math, then inspected the Spanish rendered equation. Mermaid, chart, local images
and tables were visible. Both practice links opened independent Fill-mode forms;
synthetic names were saved, the tabs closed and reopened through the guide links,
and values persisted. The test names were then cleared and saved (the initial
fields were empty). The original English interface preference was restored.

An outline click on the new regression heading landed around chapter 2 rather
than at that heading; direct scroll-bar positioning was used to inspect formulas.
Tracking: [#364](https://github.com/PinedaTec-EU/LeonardoMD/issues/364). No navigation fix is included here.
