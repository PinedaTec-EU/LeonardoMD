# Current state

The initial macOS implementation is being delivered through [issue #1](https://github.com/PinedaTec-EU/LeonardoMD/issues/1). The repository began with 15 product stories and no source code.

Run `./launch.sh`; validate with `swift test`. Generated app bundles are in ignored `output/`. There is no existing version-bump workflow.

The app supports standalone documents, workspace/project management, search, native editing, Git, portable preferences and PDF. Focus is independent of project ownership. Mermaid/math are opt-in; real WebKit tests verify disabled engines, context replacement, labeled diagrams and local images. Premium action surfaces follow the active palette in windows and sheets.

Local validation passed 42 tests (21 Core, 10 App, 8 render contracts, 3 real WebKit). See [validation](../doc/validation/macos-mvp.md) for coverage and performance limits. Settings writes merge changed fields through a shared actor; document identity scopes native undo and search state.

Do not use the image-generated concept as validation evidence. Real application captures and exact-head checks belong in the PR.

Shared skill discovery uses `AGENTS.md` and the generated `.skills/index.md`, with nine thin adapters to the sibling `ai-skills-shared` canonical source. Projection validated and idempotent against clean integrated shared source `fa144ff6a87f8bc946e1e3832dd2783aea292e22`. Tracking: [#11](https://github.com/PinedaTec-EU/LeonardoMD/issues/11).

Document mode and preferences scope use `PremiumSelection` with the shared button surface. `PremiumSwitchStyle` follows `leonardoAccent` for active states, including extensions and preferences. Tracking: [#4](https://github.com/PinedaTec-EU/LeonardoMD/issues/4).

Workspace project rename/delete updates documents by descendant path even in standalone viewer mode; similarly named sibling paths are preserved. Regression tracking: [#14](https://github.com/PinedaTec-EU/LeonardoMD/issues/14).
