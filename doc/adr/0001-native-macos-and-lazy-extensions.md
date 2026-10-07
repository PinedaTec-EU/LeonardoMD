# ADR 0001: Native macOS shell and isolated rendering engines

Date: 2026-10-07

## Decision

LeonardoMD uses Swift 6, SwiftUI and AppKit on macOS 14 or later. The native text editor preserves standard undo, selection and keyboard shortcuts. Foundation services handle files, portable JSON preferences and asynchronous Git commands. A separate renderer target owns WebKit and bundled, offline JavaScript libraries.

Two entry paths share one document editing/rendering implementation:

- **Standalone viewer:** opens a file without attaching a project or showing the folder tree. Relative assets resolve from that file's directory. Global preferences apply. Editing and opening its directory as a project are explicit actions.
- **Project:** opens a folder with lazy navigation, search, file operations and optional Git. **Focus mode** hides the folder sidebar and inspector while retaining the project and document. Leaving focus restores the requested panels.

Mermaid and math are opt-in. Their code is distributed with the app but excluded from the renderer when disabled. Changing enabled engines rebuilds the WebKit execution context and releases the old one. Deferred rendering of visible diagrams is an additional optimization, independent of plugin activation.

## Consequences

The app works offline and does not depend on a CDN to open documents. Third-party executable plugins need a separate permission/signing design; the MVP extension catalog uses bundled engines with explicit settings. Cross-platform UI implementation remains future work; portable file formats and core contracts provide the reuse boundary.

Git uses the installed system CLI and existing credentials. Operations stay asynchronous. Dirty-worktree pull and merge conflicts are surfaced rather than automatically repaired.
