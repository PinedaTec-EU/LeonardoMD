# Native acceptance evidence

Application source: `d3894c5d6ab4fb38cb4874d64b9cfa6c04e053d4`. Release app on macOS 27.0.1 / arm64, captured 2026-10-07. Nine unmodified JPEGs contain public example documents and controls. Publication authorized by the owner.

Main window: 1260 × 850 points / 2520 × 1700 pixels. Preferences: 520 × 460 points / 1040 × 920 pixels. Native AppKit/SwiftUI/WKWebView; browser viewport is not applicable.

- `project.jpg`: architecture document in reading mode with project navigation and enabled Mermaid.
- `split.jpg`: native Markdown editor beside rendered preview, project navigation visible.
- `focus.jpg`: same project in split mode with project panels hidden; exiting focus was verified to restore them.
- `standalone.jpg`: individual document without folder/project; labeled Mermaid diagram visible.
- `engines-disabled.jpg`: both motors off and Mermaid source code displayed.
- `math-local-image.jpg`: enabled engines, KaTeX formula and relative SVG displayed after outline navigation.
- `preferences.jpg`: premium palette/effect controls and switches, Graphite Glass with Microcuadrícula.

Reproduce from the application source SHA using `./launch.sh`. Open `Examples/Proyecto`, then `docs/arquitectura.md`. Use Reading, Split, Focus and Configuration. Open the same Markdown file individually with Command-O to verify standalone ownership. Use Extensions to turn both engines off and back on; the diagram changes to source code while disabled. The formula heading in the outline scrolls to the rendered formula and local SVG. Both engines were restored to their original active state.

`provenance.json` records source commit/tree, release executable and JPEG hashes. `source-inputs.txt` records versioned build inputs. The media hosting commit is distinct from the application source SHA.

Current-head CI runs 37648961427 and 37648968657 pass all 63 tests and optimized packaging. These captures do not establish sustained 60 FPS or peak-memory budgets.

The first-process file panel was inspected, but its original issue #9 scenario remains unproven: accessibility row selection and keyboard selection behaved differently. Seven document-state captures above prove the reviewed document states, not resolution of that incident.

`local-file-confirmation.jpg` (588 × 344 pixels) shows the mandatory native dialog for a document-authored relative SVG link. Clicking Cancel returned to the same document; no system handler was invoked. The public synthetic fixture is included in `local-link-fixture/`; reproduce by opening its proof.md individually and clicking its link. The default web-confirmation setting remained enabled in this native check; the six automated authorization tests additionally prove the mandatory policy when web confirmation is disabled.

`fresh-first-document.jpg` proves an additional clean-process first-document flow: quit through the native app menu; exact executable process absent verified by pgrep; relaunch to empty welcome; activate the background-launched app BEFORE opening any selector; click Open Document; select arquitectura.md with Down; observe Open enabled; click Open; standalone document renders. No selector reopening or foreground recovery occurred after that first panel appeared. This proves the keyboard selection path. The original mouse/accessibility selection discrepancy remains tracked in #9 and is not claimed resolved.
