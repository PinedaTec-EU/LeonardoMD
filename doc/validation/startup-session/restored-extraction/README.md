# Restored extraction assets in Preview and PDF

[PR #91](https://github.com/PinedaTec-EU/LeonardoMD/pull/91), [issue #90](https://github.com/PinedaTec-EU/LeonardoMD/issues/90). The synthetic project contains a red SVG at the same packaged path as a blue SVG in a sibling MDLZ extraction. The original archive is kept unchanged; the extracted MDLF has an additional paragraph.

The XCTest regression opens the project and package, extracts to the sibling directory, prepares and finishes close, serializes the session snapshot, and restores into a new DocumentTabs controller. It asserts that the selected document is the edited extraction, the project is still active, the asset resolver reads the blue SVG from the extraction, and AppKit disposes the temporary package without deleting the user-owned folder. The real WKWebView decodes the image and exports the PDF. Core Graphics rasterizes the actual PDF page and asserts that it contains blue asset pixels.

- [Native Preview after restoration](restored-extraction.png)
- [PDF exported from that restored Preview](restored-extraction.pdf)

Use `LEONARDO_VISUAL_EVIDENCE=<temporary-directory> swift test --skip-build --filter SessionRenderingPackageAssetTests` with a current build to reproduce. This is a native AppSession close/reopen regression with real WebKit, not a packaged-process relaunch. The earlier attached packaged QA demonstrates startup/quit, both preference states and both Help locales; this change touches only restoration of an already-extracted workspace, not those controls or guide content. The installed user application was left running.

Product source for the captures: `c4d68cb6fecd5918ee837f6694702200faa18d69`. The next commit adds only validation artifacts.
