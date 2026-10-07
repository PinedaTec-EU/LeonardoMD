# Current state

The initial macOS implementation is being delivered through [issue #1](https://github.com/PinedaTec-EU/LeonardoMD/issues/1). The repository began with 15 product stories and no source code.

Run `./launch.sh`; validate with `swift test`. Generated app bundles are in ignored `output/`. There is no existing version-bump workflow.

The app supports standalone documents, workspace/project management, search, native editing, Git, portable preferences and PDF. Focus is independent of project ownership. Mermaid/math are opt-in; real WebKit tests verify disabled engines, context replacement, labeled diagrams and local images. Premium action surfaces follow the active palette in windows and sheets.

Core, App, render contracts and real WebKit checks run through `swift test`; the PR records test totals and results for its current head. See [validation](../doc/validation/macos-mvp.md) for coverage and performance limits. Settings writes merge changed fields through a shared actor; document identity scopes native undo and search state.

Do not use the image-generated concept as validation evidence. Real application captures and exact-head checks belong in the PR.

Shared skill discovery uses `AGENTS.md` and the generated `.skills/index.md`, with nine thin adapters to the sibling `ai-skills-shared` canonical source. Projection validated and idempotent against clean integrated shared source `fa144ff6a87f8bc946e1e3832dd2783aea292e22`. Tracking: [#11](https://github.com/PinedaTec-EU/LeonardoMD/issues/11).

Document mode and preferences scope use `PremiumSelection` with the shared button surface. `PremiumSwitchStyle` follows `leonardoAccent` for active states, including extensions and preferences. Tracking: [#4](https://github.com/PinedaTec-EU/LeonardoMD/issues/4).

Workspace project rename/delete updates documents by descendant path even in standalone viewer mode; similarly named sibling paths are preserved. Regression tracking: [#14](https://github.com/PinedaTec-EU/LeonardoMD/issues/14).

Real symlink fixtures cover project read/delete escapes and allowed versus outside image aliases. Tracking: [#16](https://github.com/PinedaTec-EU/LeonardoMD/issues/16).

Offline rendering dependencies are pinned with hashes, npm integrity and licenses. Mermaid 11.16.1, DOMPurify 3.4.16 and KaTeX 0.18.2 replace versions affected by published advisories; see dated checks and patched-engine regression scope in [validation](../doc/validation/macos-mvp.md). Tracking: [#18](https://github.com/PinedaTec-EU/LeonardoMD/issues/18).

On 2026-10-07, the owner authorized enabling standard hosted runners in PinedaTec-EU. The organization setting `Disable for all repositories` had prevented macOS allocation; other repositories succeeded on self-hosted Linux runners. After the setting change, the Ubuntu/macOS probe and macOS application CI passed. Future allocation investigations should compare runner labels and organization policy before attributing a long queue to capacity. Evidence: [#12](https://github.com/PinedaTec-EU/LeonardoMD/issues/12).

Document tabs own complete `AppSession` instances and retain native views. `DocumentTabs` coordinates selection/deduplication, Markdown drops, close protection, Finder reveal and sibling file mutations. See [tab behavior and validation](../doc/validation/document-tabs.md). Tracking: [#19](https://github.com/PinedaTec-EU/LeonardoMD/issues/19); stacked on PR #8.
