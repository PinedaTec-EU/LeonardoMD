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
expansion, restoring original text, flush, caret-DOM preservation, re-locking and protection against a stale DOM overwriting a pending raw edit.
Existing WebKit table layout and renderer engine/security checks remain required.

## Local validation results

- Full Swift suite: 386 XCTest cases, 15 optional skips (the capture-enabled run has 14), zero failures; 12 Swift Testing renderer checks pass.
- Final focused run: two real-WebKit editing cases and eight session editing cases pass, including exact source restoration.
- Packaging/recorder Python suite: 24 cases, seven engine-dependent skips, zero failures.
- Twenty successful recorded Swift compilation commands allocate build delta 20 for source PR #145; unsuccessful/interrupted runs allocate no delta.
- Captures were inspected for solid/outlined lock states, enabled Save, explicit English/Spanish unsaved labels, and actual rendered edits.

Remote CI and independent review are separate delivery gates. These local checks do not establish integration, publication or a packaged startup acceptance.

Complete formatted-run deletion is covered by [#148](https://github.com/PinedaTec-EU/LeonardoMD/issues/148): empty bold/emphasis/strikethrough runs, including nested runs, and inline code remove their delimiters; restoring original text restores the exact original source. Whitespace-only content is retained outside empty formatting markers.

Additional regressions cover metadata-only insertion without a final newline ([#149](https://github.com/PinedaTec-EU/LeonardoMD/issues/149)), stale raw input and native marked text ([#150](https://github.com/PinedaTec-EU/LeonardoMD/issues/150)), visible preview composition at flush ([#151](https://github.com/PinedaTec-EU/LeonardoMD/issues/151)), and approved-close quiescence with cancellation recovery ([#152](https://github.com/PinedaTec-EU/LeonardoMD/issues/152)).

Conflict-copy regression [#153](https://github.com/PinedaTec-EU/LeonardoMD/issues/153) uses actual WebKit with its edit-message delivery suppressed: Save copy flushes the visible source before capturing it, blocks late input during authorization, and commits the verified saved snapshot without an asynchronous reopen. A failed destination write retains the original URL, snapshot, dirty draft and conflict. Individual-tab close is locked before asynchronous preparation, with cancellation restoring editing; a delayed authorization callback cannot insert unprompted input. The final focused native run passes 26 cases (one optional capture skip).

Pending-preview synchronization regression [#154](https://github.com/PinedaTec-EU/LeonardoMD/issues/154) delays real WebKit edit delivery before shared-buffer capture, reconciliation acquisition and external-change detection. All retain the visible draft. Buffer providers are async/throwing and callers propagate capture failures. Close waits for busy, file-operation, saving, settings, Git and reconciliation work; native tab/window checks hold busy/file counters until explicitly released.

Async document/project opening, mode/protection transitions, detach and save register operation ownership before their first suspension. Close joins that work, and final closing/stopped checks reject resumed transitions. A deterministic suspended-project-authorization regression proves that close cannot approve until the operation exits, and that no project/mode/protection transition is accepted after approval. An initial full run had one WebKit readiness timeout before editing; the unchanged-code full rerun passes all 386 XCTest cases. No successful build delta was allocated to that failed run.
