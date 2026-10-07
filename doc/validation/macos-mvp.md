# macOS MVP validation

Run `swift test` for Core, App, static render and real WKWebView integration checks. Run `./scripts/build-app.sh` for the optimized, locally signed native bundle; `./launch.sh` opens it. Tests use disposable local folders and bare Git remotes, never a production remote.

Coverage includes workspace/file operations, path and symlink boundaries, streamed search/cancellation, schema and stale-window settings merges, external-change protection, navigation isolation, Git dirty/conflict handling, Unicode/newline paths, multi-megabyte process output, and fetch/pull/push against a local bare remote. Real WebKit checks verify sanitization, disabled engine globals, retained content-update context, Mermaid labels, KaTeX, parent-relative images, PDF data and engine context replacement.

Native visual acceptance uses `Examples/Proyecto/docs/arquitectura.md`: standalone viewer, project navigation, focus with panel restoration, split editor, optional extensions and palette controls. Author-owned screenshots are attached to the implementation PR with their source commit, viewport and state. Development findings are tracked in [#2](https://github.com/PinedaTec-EU/LeonardoMD/issues/2), [#3](https://github.com/PinedaTec-EU/LeonardoMD/issues/3), [#4](https://github.com/PinedaTec-EU/LeonardoMD/issues/4), [#5](https://github.com/PinedaTec-EU/LeonardoMD/issues/5), [#6](https://github.com/PinedaTec-EU/LeonardoMD/issues/6) and [#7](https://github.com/PinedaTec-EU/LeonardoMD/issues/7).

## Performance evidence and limits

The application emits OSLog metrics under `eu.pinedatec.LeonardoMD`: `application_window_ready`, `document_opened`, and `markdown_render_ready`. The renderer reports JavaScript Markdown duration separately from initial page load duration, so engine/resource loading is not confused with parsing.

Development fixture measurements on macOS 27 / arm64 with Swift 6.4 include document read/open times around 0.2–0.6 ms and Markdown JavaScript processing around 1–7 ms. These are small disposable fixtures, not cold-start or sustained-scroll guarantees. The PR records optimized native sample measurements for the reviewed commit.

US.000011 budgets remain targets. Sustained 60 fps, peak memory on very large documents and a multi-device performance matrix require profiling beyond this smoke validation. Disabled engines are proven absent from the resource allowlist, HTML scripts and JavaScript globals; disabling replaces and detaches the old context. This proves loading isolation, not a precise operating-system RSS release amount.

The MVP polls external file/configuration changes every two seconds, loads tree children on expansion, streams searches and debounces preview updates. Git and file operations run asynchronously. User input is protected while a document navigation is reading from disk; Git navigation stays on its initiating project until completion.
