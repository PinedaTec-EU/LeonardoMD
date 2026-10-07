# Exact-head native acceptance captures

Source: `fd1b55fa889c0ea03927dbb2ece8f797d319ae88`, PR https://github.com/PinedaTec-EU/LeonardoMD/pull/8.

Captured 2026-10-07 approximately 12:54–12:58 UTC on macOS 27.0.1 / arm64 using a release app rebuilt at this SHA after quitting the previous process. Native AppKit/SwiftUI with embedded WKWebView; browser does not apply. Main document captures are 2520 × 1700 pixels (1260 × 850 points); welcome is 2494 × 1688 pixels; preferences 1040 × 920 pixels; About 568 × 332 pixels. All images are unedited native CUA captures and show only the repository's synthetic example content, standard application controls and the approved icon. Every image was visually inspected before public publication; no private document, credential, personal contact or unrelated application content is included. Local logs and native selector inventories are deliberately excluded from this published set.

- `welcome.jpg`: startup and primary controls.
- `standalone.jpg`: independent Markdown, no project sidebar, engines disabled.
- `mermaid.jpg`: Mermaid active with visible labels.
- `math-local-image.jpg`: KaTeX formula and parent-relative local SVG.
- `preferences.jpg`: palette-aware preference controls.
- `project.jpg`: project tree and inspector.
- `focus.jpg`: preserved document with project panels hidden.
- `split-restored.jpg`: restored panels and native editor with rendered preview.
- `about-icon.jpg`: native About panel showing the approved bundle icon.

## Reproduce

At the source SHA, run `./launch.sh`. In Stage Manager, use Window → Bring All to Front before interacting or capturing. Open `Examples/Proyecto/docs/arquitectura.md` through Open document; its first selection enables Open. Toggle both extensions off and on, choose the relevant outline sections, and open Preferences. Open `Examples/Proyecto` as project, expand docs, toggle focus twice, choose Split, and open About.

42 local tests and release packaging pass at this source SHA; strict deep code-signature verification also passes. Remote CI has no result because organization policy disables standard hosted runners (issue #12). Local test/build logs remain available to the judge and are not asserted to be hosted CI.

These captures do not prove sustained 60 FPS, large-file peak memory or a multi-device performance matrix; see the source `doc/validation/macos-mvp.md` for limits.
