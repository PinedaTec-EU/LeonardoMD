# Native acceptance evidence

Application source: `d3894c5d6ab4fb38cb4874d64b9cfa6c04e053d4`. Release app on macOS 27.0.1 / arm64, captured 2026-10-07. Seven unmodified JPEGs contain public example documents and controls. Publication authorized by the owner.

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

The first-process file panel was inspected, but its original issue #9 scenario remains unproven: accessibility row selection and keyboard selection behaved differently. Seven captures above prove the reviewed document states, not resolution of that incident.
