# Current state

The initial macOS implementation is being delivered through [issue #1](https://github.com/PinedaTec-EU/LeonardoMD/issues/1). The repository began with 15 product stories and no source code.

Run `./launch.sh`; validate with `swift test`. Generated app bundles are in ignored `output/`. There is no existing version-bump workflow.

The app supports standalone documents, workspace/project management, search, native editing, Git, portable preferences and PDF. Focus is independent of project ownership. Mermaid/math are opt-in; real WebKit tests verify disabled engines, context replacement, labeled diagrams and local images. Premium action surfaces follow the active palette in windows and sheets.

Local validation passed 42 tests (21 Core, 10 App, 8 render contracts, 3 real WebKit). See [validation](../doc/validation/macos-mvp.md) for coverage and performance limits. Settings writes merge changed fields through a shared actor; document identity scopes native undo and search state.

Do not use the image-generated concept as validation evidence. Real application captures and exact-head checks belong in the PR.
