# Native acceptance evidence

Application source: `61dadd5290ffb69a7fdd47d1b17f51c5c3d17819`. Native release app, macOS 27.0.1 / arm64. Captured 2026-10-07 approximately 13:46–13:47 UTC. Seven unmodified JPEGs show only public repository example documents and app controls. Publication explicitly authorized by the owner in the implementation chat.

Main window: 1260 × 850 points / 2520 × 1700 pixels. Preferences: 520 × 460 points / 1040 × 920 pixels. Native AppKit/SwiftUI/WKWebView; browser viewport is not applicable.

Screens: standalone welcome without folder; project/native split; Mermaid labels; formula/relative SVG; focus retaining project; restored panels/disabled engines; premium preferences.

Reproduce from application source SHA with `./launch.sh`. Open `Examples/Proyecto/bienvenida.md` individually, then open `Examples/Proyecto` and its architecture document. Use Reading/Split, Extensions, heading navigation, Focus and Configuration controls.

`provenance.json` records the application source commit/tree, current release binary fingerprint and capture hashes. `source-inputs.txt` records versioned application/build inputs. This branch is immutable media storage; its hosting commit is distinct from the application source commit. Captures were taken from the latter release package.

Both application-source macOS CI runs passed: 37630232606 and 37630242527, including 45 tests and optimized packaging. Performance/RSS/60-FPS targets are not established by these captures. Symlink automated-coverage wording is tracked separately in issue #16.
