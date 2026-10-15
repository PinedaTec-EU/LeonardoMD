# Protected document editing

Tracking: [#144](https://github.com/PinedaTec-EU/LeonardoMD/issues/144).

Each newly opened document starts protected. `lock.fill` is solid; the writable
`lock.open` is outlined and attenuated. Protection affects preview and raw input
without saving or discarding the draft. Saving is manual (toolbar or Command-S).
Dirty tabs show an explicit label, the active filename shows Unsaved changes,
and navigation, tab/window closure and application quit offer Save/Discard/Cancel.
Cancellation or a failed save keeps the draft. Cancel also stops the quit sequence.

Preview input edits mapped Markdown text leaves instead of converting the entire
HTML document back into Markdown. Text, explicit link labels, ordinary table cells
and code share the raw draft. Empty documents have an editable insertion area.
Raw HTML, generated math and Mermaid, and structural changes use raw Edit.
A native expected-buffer check rejects stale/unauthorized edits. Save, mode changes,
protection and close flush the WebKit buffer before proceeding; window close does
not skip that barrier based on a potentially stale native dirty flag.

## Evidence

Native captures on 2026-10-15, macOS 27.0.1 arm64, SwiftPM development XCTest host:

- `protected-editing/editing-{en,es}-protected.png`: real WorkspaceView, protected raw editor.
- `protected-editing/editing-{en,es}-unsaved.png`: writable raw editor, explicit dirty label and Save button.
- `protected-editing/preview-edited.png`: actual WKWebView snapshot after editing heading, formatted text, a table and code.

Workspace viewport: 1260×850 points (2520×1700 pixels). Preview viewport:
800×600 points. Synthetic local Markdown, isolated temporary preferences/files.
The development version visible in hosting captures comes from XCTest rather
than a packaged LeonardoMD artifact. These are native component captures, not
fresh packaged-process or owner's running-application acceptance. No running
LeonardoMD instance was terminated or replaced.

Regression checks exercise protection/relocking, manual save, stale draft rejection,
Save/Discard/Cancel, conflict retention and inactive-tab/window cancellation.
Real WebKit tests exercise source/front-matter/CRLF preservation, successive edits
with shifting ranges, a row value matching a table separator, code delimiter
expansion, restoring original text, flush, caret-DOM preservation and re-locking.
Existing WebKit table layout and renderer engine/security checks remain required.

## Local validation results

- Full Swift suite: 377 XCTest cases, 14 optional skips, zero failures; 12 Swift Testing renderer checks pass.
- Final focused run: two real-WebKit editing cases and five session editing cases pass, including exact source restoration.
- Packaging/recorder Python suite: 24 cases, seven engine-dependent skips, zero failures.
- Six successful recorded Swift compilation commands allocate build delta 6 for source PR #145; unsuccessful/interrupted runs allocate no delta.
- Captures were inspected for solid/outlined lock states, enabled Save, explicit English/Spanish unsaved labels, and actual rendered edits.

Remote CI and independent review are separate delivery gates. These local checks do not establish integration, publication or a packaged startup acceptance.
