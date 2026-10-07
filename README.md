# LeonardoMD native validation evidence

Reviewed source: `782f5a6525ea777be3671d82cb114097dc8a420a` for https://github.com/PinedaTec-EU/LeonardoMD/pull/8.

Captured 2026-10-07 on macOS 27 arm64, locally built release application, using native CUA screenshots. These are actual application captures, unedited; no generated mockups. Main window 1260 × 850 points / 2520 × 1700 pixels. Preferences sheet 520 × 460 points / 1040 × 920 pixels. JPEG bytes preserved.

- `welcome-premium.jpg`: startup and premium primary controls.
- `standalone.jpg`: independent document, no folder, optional engines disabled.
- `mermaid-enabled.jpg`: optional engines activated; labels visible.
- `math-local-image.jpg`: KaTeX formula and relative local SVG rendered.
- `preferences-premium.jpg`: palette accent propagated to sheet buttons.
- `project.jpg`: project tree and extension inspector.
- `focus.jpg`: panels hidden while project remains attached.
- `split-restored.jpg`: exiting focus restores both panels; native editor plus preview.

All files under `doc/evidence/782f5a6/`. `swift-test.log`: 42 tests pass (Core 21, App 10, render 8, real WKWebView 3). `release-build.log`: successful optimized release build. `native-metrics.log`: current release process only, small sample document; timings do not establish large-file throughput, peak memory, or sustained 60 FPS.

GitHub macOS jobs were queued at publication, so these local results do not assert CI success or a final judge PASS.
