# Packaged Help smoke evidence

## Identity and scope

- PR head reviewed for this evidence: `cbb3ea9f96a81f59bcec95c439e381b896b407bd`.
- Product implementation source under review: `052feadc5c2991892b96f6a20a26e000306c5830`.
- Date: 2026-11-11 (Europe/Madrid).
- Host: macOS 27.0.1, build `26A434`.
- Tested process: PID `62226`, started `Wed Nov 11 00:25:50 2026`.
- QA bundle: `/private/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-qvgcv5f7/LeonardoMDQA.app`.
- Executable: `LeonardoMD`; bundle identifier `eu.pinedatec.LeonardoMD.qa.c848b2cf44624cf5a0ba1e8c1b3cf6a7`; version `0.3.1276`; build `1276`.

This was a live disposable QA process with a standard first window. The installed
`/Applications/LeonardoMD.app` process was not terminated or modified.

## Help workflow

Help was opened from the QA application's real Help menu, not from a static
resource browser.

| Locale | Bundled guide | Live document URL |
|---|---|---|
| English | `Guide-v52-en.mdlz` | `file:///Users/jmr.pineda/Library/Application%20Support/LeonardoMD/User%20Guides/v52/en/Guide-v52-en.mdlz` |
| Spanish | `Guide-v52-es.mdlz` | `file:///Users/jmr.pineda/Library/Application%20Support/LeonardoMD/User%20Guides/v52/es/Guide-v52-es.mdlz` |

The language was changed through Preferences → General → On this Mac →
Language, then Help was closed and reopened to exercise both bundled guides.
Native accessibility trees and the live window were inspected for both locales.

With Mermaid, Mathematics and Vega-Lite enabled (Citations disabled and
Markdown extras enabled), both guides showed:

- a rendered Mermaid image and a rendered Vega-Lite chart;
- local images and tables from the package;
- rendered inline and display mathematics, including the mean, underbrace,
  radical/long-arrow example and the tagged box-counting equation `(1)`;
- no KaTeX error or literal delimiter in the rendered equation nodes; and
- code examples remaining literal source by design.

## Disabled-extension fallback

In the Spanish guide, Preferences → Extensions → Matemáticas was switched off
and the preferences sheet was closed. The live document presented the actual
recommendation sheet with identifier `extension-recommendation-dialog`, naming
Matemáticas and offering `Ahora no` / `Activar extensiones`. After choosing
`Ahora no`, the live accessibility tree showed the fallback source literally,
including `$$\\bar{x}=...$$`, `$$ \\underbrace{...} $$`, `\\sqrt`, and
`\\tag{1}`. The rendered math containers were absent in this state. This
confirms that disabling the extension preserves visible source notation rather
than silently dropping the content.

Matemáticas was then enabled again through the same Preferences flow. A fresh
live accessibility inspection showed the rendered fraction/overbar, underbrace,
radical/arrow and tagged equation `(1)` containers again; the guide remained
open and saved.

## Separate practice-form smoke

The practice link in each guide was opened in the same QA process. Synthetic
values were entered, saved with `⌘S`, the form tab was closed, and the form was
reopened through the guide link. The values and the `Saved · local file` status
were present after reopening in both English (`Practice-v1-en.mdlr`) and Spanish
(`Practice-v1-es.mdlr`).

## iOS evidence

The completed simulator result is recorded outside the repository at
`/tmp/leonardo-423-evidence.h9ZIHc/ios-ondemand-1794353309.xcresult`.
`xcresulttool` reports:

- device: iPhone 18 Pro, arm64, iOS Simulator 27.0, OS build `24A434`;
- test plan: `LittleLeonardo`;
- suite/test: `OnDemandSyncUITests/testCatalogueContextRetentionAndSeparateCache()`;
- result: 1 passed, 0 failed, 0 skipped, duration 2m 30s; and
- fixture phase: `finish` in `/tmp/leonardo-423-ondemand.Jecsu2`.

## Packaging limitation

The package inspection record in [package-inspection.json](package-inspection.json)
still reports `fresh_process_launched: false` for its automated output-bundle
probe. It also records executable identity, version, no `XCTest.framework`
dependency, signed helper/Sparkle dependencies and verification of the bundle.
The live PID and Help observations above are separate evidence from that probe;
they do not retroactively change the probe field. No new compilation was run for
this follow-up.
