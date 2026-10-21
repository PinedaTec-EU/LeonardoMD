# Native hover evidence for PR #262

Reviewed source: `877f7df5ddab895db818087c51bbd94065493d75`.

Native macOS SwiftUI/AppKit app, no browser or URL. Window 1200×850 points, screenshots 2400×1700 pixels. All data is synthetic. Captures show Home favorites/document hover, Home project hover, recent-document hover, sidebar folder hover, selected file idle/hover, and sidebar search hover. Idle captures show pointer exit removes the transient background; selection persists. Folder expansion and document opening were exercised through accessibility actions.

Reproduce from the PR checkout: `LEONARDO_SOURCE_PR=262 ./launch.sh --qa` (records a compilation; do not run merely to inspect captures). Quit the existing app normally first; a separate bundle ID does not bypass single-instance ownership. Open a synthetic folder with a Markdown document and child folder, move the pointer across complete rows, expand a child folder, open a document, move away and back, then search by filename. In a new tab inspect Favorites and Recents; move across both text and empty row space. Scroll Home when recent entries are below the viewport. Observe the background returns to idle on exit and the selected row retains its base highlight.

The temporary QA bundle is a copy of the real app; plist/executable/dependencies and local signature were validated. Startup PID 80205 reached application_ready. The code was compiled before the final ledger-only commit; `provenance.json` binds the identical Sources tree and executable hash to the current reviewed head. No product source changed after compilation. Captures are untouched native window captures from screencapture, with native CoreGraphics pointer events explicitly authorized by the owner after CUA failed under Stage Manager.
