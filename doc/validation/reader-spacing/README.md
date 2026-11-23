# iOS synchronized reader spacing — #397

The owner reported the excessive gap in the Classic reader on a physical iPhone.
The unmodified supplied screenshot is [owner-report.png](owner-report.png), captured
on 7 November 2026 at 20:30:32 Europe/Madrid. The exact installed build and browser
viewport were not reconfirmed in that report; no metadata is invented for it.

## Native evidence

Producer source: `560627b21b9032f68edb0b5fba2c2d67b6f39a0d`.
The final author run used an iPhone 18 Pro simulator, iOS 27.0 (24A434), device
`A5A73B11-EE27-40AC-ABAB-CADF1B85143B`. Both native XCTest cases passed.
These are original UIKit window captures containing production WKWebView rendering
with fictional Spanish content, not a physical-device or TestFlight installation claim.

| Original | Scenario |
| --- | --- |
| [Default reader](default-reader.png) | Production renderer with its unchanged default configuration, matching the previous spacing |
| [Compact renderer](compact-renderer.png) | Same renderer and document, with the reader option enabled |
| [Synchronized reader](synchronized-reader.png) | Actual `MobileDocumentView`, loaded from a synthetic offline project through `MobileLibrary` |

Each PNG has a `.context.json` and canonical `.metadata.json` beside it. Capture
times come from the XCTest attachment manifest, retained in
[capture-manifest.json](capture-manifest.json), rather than metadata collection time.
The native window is 402×874 points (1206×2622 pixels); its web viewport is 402×724.
The native test did not query a User-Agent, so the browser version is explicitly unavailable.
The synchronized document is mounted in a test-owned NavigationStack, with its
real Preview/Source and synchronization toolbar, without live enrollment or HTTP.

[Measured geometry](layout-metrics.json) confirms:

- First heading top: **98.3125 → 16 CSS pixels**.
- Later heading margin: **42.234375 CSS pixels** in both configurations.
- The long document remains taller than its viewport and can scroll.
- Restoring the default configuration restores its original geometry.

The regression also checks the production synchronized-document view, not only
the renderer option. It fails if that view stops enabling compact spacing.
The default option remains false; desktop callers retain their existing spacing.

## Source binding and reproduction

[producer-inputs.json](producer-inputs.json) records SHA-256 values for all 646
tracked source, test, project, package, script, asset and workflow inputs. The
source was committed before the final iOS capture run. Subsequent ledger-only
bookkeeping does not enter the compiled products. The packaged iOS `preview.css`
was independently checked byte-for-byte against the source stylesheet.

Later evidence-only commits add this record and captures. Verify their source
equivalence with:

```sh
git diff --exit-code 560627b21b9032f68edb0b5fba2c2d67b6f39a0d HEAD -- Sources Tests Mobile assets scripts Package.swift Package.resolved launch.sh .github
```

Reproduce the native checks through the repository compilation recorder:

```sh
python3 scripts/compile-and-record.py --pr-number 405 -- xcodebuild -project Mobile/LittleLeonardo.xcodeproj -scheme LittleLeonardo -destination 'platform=iOS Simulator,id=A5A73B11-EE27-40AC-ABAB-CADF1B85143B' -derivedDataPath .build/little-ios-397 -parallel-testing-enabled NO -only-testing:LittleLeonardoTests/MobileReaderSpacingTests CODE_SIGNING_ALLOWED=NO test
```

Local validation also passed 717 XCTest cases (36 opt-in skips), 72 Swift Testing
cases, the focused guide/renderer checks and all three deterministic guide-package
tests. Guide v31 explains Preview/Source reading in both languages, preserving
previous personal guide copies and practice answers. Publication to the owner's
existing internal TestFlight group follows integration and version materialization;
the physical iPhone visual confirmation remains separate.

## Packaged bilingual help

[Guide31 acceptance](help31/validation.json) records the fresh packaged QA
process PID 2544, baseline version/build 0.3.1136/1136, both actual Help-menu
workflows and matching personal/bundled package hashes. Fourteen original
captures and sidecars cover Mermaid, inline and display math (including the
tagged box-counting equation), literal code and Math-disabled fallback, charts,
local images, tables, and both separate practice forms filled, saved, closed and
reopened. Native Help contexts explicitly report bitmap-equivalent capture
geometry rather than claiming a browser CSS viewport. The app quit normally;
all three retained preferences/practice originals were restored byte-for-byte,
with synchronization preferences unchanged. The installed sync helper was not
replaced or stopped during this QA.

[producer-tree.json](producer-tree.json) also binds the entire producer tree,
including version, release metadata and guide sources, excluding only this PR's
mutable compilation entry. Later evidence adds only this validation directory
and ledger bookkeeping. This is the evidence-only mapping expressly permitted
by the shared visual-capture metadata contract; captures retain their authentic
producer revision instead of being restamped as a later Git commit.
