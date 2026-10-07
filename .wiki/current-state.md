# Current state

The initial macOS implementation is being delivered through [issue #1](https://github.com/PinedaTec-EU/LeonardoMD/issues/1). The repository began with 15 product stories and no source code.

Run `./launch.sh`; validate with `swift test`. Generated app bundles are in ignored `output/`. There is no existing version-bump workflow.

Startup diagnostics emit synchronous stderr JSON plus unified-log notice records (`eu.pinedatec.LeonardoMD`, category `startup`) before AppKit initialization through first-window readiness. Metadata excludes paths, document content, arguments and environment values. [Bug #31](https://github.com/PinedaTec-EU/LeonardoMD/issues/31) reproduced a HIServices registration abort with the original QA binary inside the agent execution sandbox; the identical binary started outside it. Retained system logs did not identify the specific denied operation. Use packaged GUI launches outside the execution sandbox for native QA; see README diagnostics.

The app supports standalone documents, workspace/project management, search, native editing, Git, portable preferences and PDF. Focus is independent of project ownership. Mermaid/math are opt-in; real WebKit tests verify disabled engines, context replacement, labeled diagrams and local images. Premium action surfaces follow the active palette in windows and sheets.

Core, App, render contracts and real WebKit checks run through `swift test`; the PR records test totals and results for its current head. See [validation](../doc/validation/macos-mvp.md) for coverage and performance limits. Settings writes merge changed fields through a shared actor; document identity scopes native undo and search state.

Do not use the image-generated concept as validation evidence. Real application captures and exact-head checks belong in the PR.

Shared skill discovery uses `AGENTS.md` and the generated `.skills/index.md`, with nine thin adapters to the sibling `ai-skills-shared` canonical source. Projection validated and idempotent against clean integrated shared source `fa144ff6a87f8bc946e1e3832dd2783aea292e22`. Tracking: [#11](https://github.com/PinedaTec-EU/LeonardoMD/issues/11).

Document mode and preferences scope use `PremiumSelection` with the shared button surface. `PremiumSwitchStyle` follows `leonardoAccent` for active states, including extensions and preferences. Tracking: [#4](https://github.com/PinedaTec-EU/LeonardoMD/issues/4).

Workspace project rename/delete updates documents by descendant path even in standalone viewer mode; similarly named sibling paths are preserved. Regression tracking: [#14](https://github.com/PinedaTec-EU/LeonardoMD/issues/14).

Real symlink fixtures cover project read/delete escapes and allowed versus outside image aliases. Tracking: [#16](https://github.com/PinedaTec-EU/LeonardoMD/issues/16).

Offline rendering dependencies are pinned with hashes, npm integrity and licenses. Mermaid 11.16.1, DOMPurify 3.4.16 and KaTeX 0.18.2 replace versions affected by published advisories; see dated checks and patched-engine regression scope in [validation](../doc/validation/macos-mvp.md). Tracking: [#18](https://github.com/PinedaTec-EU/LeonardoMD/issues/18).

On 2026-10-07, the owner authorized enabling standard hosted runners in PinedaTec-EU. The organization setting `Disable for all repositories` had prevented macOS allocation; other repositories succeeded on self-hosted Linux runners. After the setting change, the Ubuntu/macOS probe and macOS application CI passed. Future allocation investigations should compare runner labels and organization policy before attributing a long queue to capacity. Evidence: [#12](https://github.com/PinedaTec-EU/LeonardoMD/issues/12).

Project browsing and both search APIs omit symbolic links; create/rename/move/delete reject symlink components and destinations, including dangling aliases, to preserve entries and targets. `Sources/LeonardoCore/LocalProjectRepository.swift` and 11 repository regressions implement this preflight boundary; it does not claim protection against concurrent path replacement (TOCTOU). Tracking: [#25](https://github.com/PinedaTec-EU/LeonardoMD/issues/25); details in [validation](../doc/validation/macos-mvp.md).

Document-authored Markdown/text links navigate inside the app; other local file links require confirmation independently of the web-link preference. `SessionRendering.followLink` and `WorkspaceView` display the target before system activation; cancel and session close discard authorization. Six link regressions and the native dialog validate the policy. Tracking: [#26](https://github.com/PinedaTec-EU/LeonardoMD/issues/26); [ADR](../doc/adr/0001-native-macos-and-lazy-extensions.md).
The branded About window is isolated in `Sources/LeonardoApp/AboutWindow.swift`; the application delegate retains one controller and routes the existing menu item to it. The approved banner is a processed executable-target resource. Version text reads `CFBundleShortVersionString` and `CFBundleVersion` from the running bundle; packaged metadata starts at 0.1.0 (build 1), matching the update feature's initial metadata. Direct SwiftPM execution without version metadata is identified as development. Tracking: [#27](https://github.com/PinedaTec-EU/LeonardoMD/issues/27). PR #28 is integrated in main.
Document tabs own complete `AppSession` instances and retain native views. `DocumentTabs` coordinates selection/deduplication, Markdown drops, close protection, Finder reveal and sibling file mutations. See [tab behavior and validation](../doc/validation/document-tabs.md). Tracking: [#19](https://github.com/PinedaTec-EU/LeonardoMD/issues/19); PR #21 targets current main after #8 and #28 integration. Native item-provider decoding is shared and regression-tested; unsupported external sidebar files cannot enter the internal relocation path.

Sidebar external-drop correction: [#34](https://github.com/PinedaTec-EU/LeonardoMD/issues/34).

Single-instance launching is coordinated by `SingleInstance` using a named CFMessagePort per bundle identifier/login session. `ApplicationDelegate` queues launch requests and opens external documents in tabs, selecting duplicates across windows. See [launch behavior and process validation](../doc/validation/single-instance.md). Tracking: [#22](https://github.com/PinedaTec-EU/LeonardoMD/issues/22), targeting main after PR #21 integration. Quit versions without the protocol before starting the updated app.

CFMessagePort caches remote endpoints within a sender process. Keep reply-bearing sends serialized off the UI thread through the asynchronous `SingleInstance.forward` boundary; the concurrent regression prevents reply transport failures. Tracking: [#23](https://github.com/PinedaTec-EU/LeonardoMD/issues/23).

Preferences groups General and Extensions tabs. Extension mutations accept explicit global/project scope; project inheritance remains portable. The document inspector only navigates headings. Tracking: [#29](https://github.com/PinedaTec-EU/LeonardoMD/issues/29), targeting main after PR #8 integration.
