# Exact-head native captures

Source head: `f2262f5c56fed4cad603015f5837b2e6a5bd8c42`.
Captured 2026-10-07 from the optimized app packaged at this source head, on macOS 27 / arm64. Unedited CUA native captures show only public example documents and app controls. Browser: N/A, native SwiftUI/AppKit/WKWebView.

Main window: 1260 × 850 points, 2520 × 1700 pixels. Preferences: 520 × 460 points, 1040 × 920 capture pixels, including native sheet context.

- preferences.jpg: project scope, matching buttons and active/neutral switches.
- split.jpg: project welcome file in split mode, Dividida selected.
- mermaid.jpg: architecture diagram with labeled nodes and active switches.
- math-local-image.jpg: formula and parent-relative SVG image.
- focus.jpg: retained project identity with panels hidden.
- engines-disabled.jpg: restored project panels and both engines disabled.
- standalone.jpg: architecture file in standalone viewer without project tree.

Reproduction: check out the source head, run ./launch.sh, open Examples/Proyecto as project and choose bienvenida.md or docs/arquitectura.md. Use the mode buttons, Extensions, inspector heading jumps, Configuration and focus button. The folder menu's Ver solo este documento switches to standalone ownership. These public fixture documents require no private user content.

Local tests, optimized packaging and exact-head hosted macOS CI pass. Performance profiling limits remain in doc/validation/macos-mvp.md. These captures do not prove sustained frame-rate or peak-memory budgets.

Publication of native app captures in this public PR was explicitly authorized by the owner in the implementation chat. JPEG bytes are unchanged; extensions match the actual native screenshot format.
