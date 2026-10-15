# Markdown association native evidence

Issue [#133](https://github.com/PinedaTec-EU/LeonardoMD/issues/133), PR [#134](https://github.com/PinedaTec-EU/LeonardoMD/pull/134).

Captured 2026-10-15 from native XCTest component windows on macOS 27 using synthetic sessions, isolated UserDefaults and a fake association driver. `source-hashes.json` binds all changed runtime/UI/test inputs; verify these hashes at the reviewed PR head. No user defaults, document associations, installed bundle or running product instance were changed by these tests.

- `prompt-screen-en/es.png`: real NSAlert window composited by WindowServer using `screencapture -l`; intrinsic geometry (260×350 points on this host). AppKit may reorder the Escape/cancel button. The test process supplies its own icon; the installed product uses its bundle icon.
- `association-en/es-other.png`: General association component, 532×350 points, other default application.
- `association-es-suppressed.png`: opt-out retained while manual action stays available.
- `association-es-failed.png`: cancelled/failed change, current state retained and retry available.
- `general-project-en/es.png`: full Preferences at 580×620 points with a synthetic project selected. Association controls remain machine-global; the native glass tab bar is not fully rasterized by bitmap capture. The form scrolls to the remaining project preferences.

## Reproduce

Run `swift test --skip-build --filter MarkdownAssociationVisualTests` after compiling the reviewed source, with `LEONARDO_ASSOCIATION_EVIDENCE` set to an external destination and optional `LEONARDO_ASSOCIATION_SCREEN_CAPTURE=1` for compositor screenshots (requires Screen Recording access). Compiling commands must use the repository compilation recorder with PR 134.

CI automatically exports component/prompt bitmap captures through `LEONARDO_VISUAL_EVIDENCE` and its existing artifact upload. Bitmap prompt captures omit some compositor button pixels; button titles are asserted and the committed `prompt-screen-*` files provide the real local compositor evidence.

Limits: this proves native components and policy integration through tests, not a fresh packaged startup or actual macOS consent interaction. The owner’s installed LeonardoMD stays running and holds product-wide single-instance ownership.
