# Native acceptance evidence

Application source: `4bf41728f73b7c71afac810adb846c54d2e76348`. Release app rebuilt from this commit on macOS 27.0.1 / arm64 and captured 2026-10-07. Eight unmodified JPEGs contain public synthetic example documents and controls. Publication authorized by the owner.

Main window: 1260 × 850 points / 2520 × 1700 pixels. Preferences: 520 × 460 points / 1040 × 920 pixels. Confirmation: 294 × 172 points / 588 × 344 pixels. Native AppKit/SwiftUI/WKWebView; browser viewport is not applicable.

- `standalone.jpg`: clean-process FIRST document opening by keyboard, no project folder, rendered labeled Mermaid.
- `project.jpg`: reading with expanded project navigation and enabled Mermaid.
- `split.jpg`: native editor beside rendered preview with project navigation.
- `focus.jpg`: reading mode with both project panels hidden; exiting focus restored them.
- `engines-disabled.jpg`: both optional motors disabled, Mermaid source fallback.
- `math-local-image.jpg`: engines restored, rendered KaTeX formula and local SVG.
- `preferences.jpg`: premium palette/effect controls and switches.
- `local-file-confirmation.jpg`: mandatory local-file dialog with target URL; Cancel returned to the same document without activating a system handler.

The standalone capture was made after quitting the previous process, verifying its executable absent, rebuilding and relaunching to welcome, and activating the app BEFORE opening any selector. Open Document was clicked once; Down selected arquitectura.md, Open became enabled, and clicking Open rendered the document. There was no selector reopening or foreground recovery after that first selector appeared. This proves the keyboard selection path. The original mouse/accessibility selection discrepancy remains tracked in #9 and is not claimed resolved.

Reproduce with ./launch.sh at the application source SHA. Open Examples/Proyecto, expand docs, open arquitectura.md and exercise Reading, Split and Focus. Open the same file individually for standalone mode. Extensions switches disable both engines and restore them; use the formula outline entry to display KaTeX/local SVG. Both motors were restored active. Open local-link-fixture/proof.md individually and click its SVG link to reproduce the dialog. Native web confirmation remained enabled; six automated authorization tests prove that local-file confirmation is also mandatory with web confirmation disabled.

provenance.json records exact application source/tree, rebuilt release executable and capture hashes; source-inputs.txt records versioned build inputs. The media hosting commit is distinct from the application source SHA. Source build inputs and release binary are identical to d3894c5 because the new commit only updates .wiki memory.

Current-head CI runs 37652322714 and 37652316798 pass 63 tests and optimized packaging. These captures do not establish sustained 60 FPS or peak-memory budgets.
