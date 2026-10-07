# macOS MVP validation

Run `swift test` for Core, App, static render and real WKWebView integration checks. Run `./scripts/build-app.sh` for the optimized, locally signed native bundle; `./launch.sh` opens it. Tests use disposable local folders and bare Git remotes, never a production remote.

Coverage includes workspace/file operations, path and symlink boundaries, streamed search/cancellation, schema and stale-window settings merges, external-change protection, navigation isolation, Git dirty/conflict handling, Unicode/newline paths, multi-megabyte process output, and fetch/pull/push against a local bare remote. Real WebKit checks verify sanitization, disabled engine globals, retained content-update context, Mermaid labels, KaTeX, parent-relative images, PDF data and engine context replacement.

Project browsing and both search APIs omit symbolic links. File operations reject symbolic link components and destinations, including dangling links, instead of resolving an alias and mutating its target. This is a preflight boundary, not protection against another process swapping paths concurrently; the correction is tracked in [#25](https://github.com/PinedaTec-EU/LeonardoMD/issues/25).

Real filesystem symlink fixtures verify that project operations reject reading or deleting outside the project and preserve the outside file. Image resolution rejects a symlink to an outside image while accepting an alias that remains inside the asset root. This scope corrects the previously unsupported coverage claim tracked in [#16](https://github.com/PinedaTec-EU/LeonardoMD/issues/16).

Local hyperlink authorization regressions cover mandatory confirmation for non-Markdown file links even with web confirmation disabled, cancellation without system activation, one-time activation of the displayed target, internal Markdown navigation, configurable web confirmation and discarding pending authorization when the session closes. System activation is injected at the application boundary, so tests never launch another application. The policy and correction are tracked in [#26](https://github.com/PinedaTec-EU/LeonardoMD/issues/26).

## Startup diagnosis

[Issue #31](https://github.com/PinedaTec-EU/LeonardoMD/issues/31) covers a temporary QA binary aborting inside HIServices during `NSApplication.shared`. The original binary's UUID matches the supplied report. A controlled direct launch of that same binary aborted inside the agent execution sandbox, while a direct launch outside it registered successfully and emitted `application_window_ready`. The second user-supplied crash report corresponds to the controlled sandbox reproduction. System-log queries found no retained failure record identifying the specific denied operation; the result isolates the execution context, not the exact underlying macOS check.

The startup tracer emits synchronous stderr JSON before AppKit and notice-level unified logs through first-window readiness. Tests verify JSON-line framing with embedded newlines/quotes, the context field allowlist, and continuation after a throwing stderr sink. A release-app smoke check outside the execution sandbox verifies 14 ordered startup phases, monotonic timing, consistent PID, main-thread execution and app-bundle metadata; both stderr and unified-log records are checked. The existing `application_window_ready` metric remains intact. This does not prove recovery from SIGABRT or a sandbox-compatible GUI launch.

## Bundled dependency validation

`THIRD_PARTY_SOURCES.json` records pinned versions, npm tarball integrity and resource SHA-256 hashes; license texts accompany the offline assets. The 2026-10-07 GitHub advisory check returned no applicable published advisories for Mermaid 11.16.1, DOMPurify 3.4.16, KaTeX 0.18.2, marked 15.0.7 and highlight.js 11.12.0. This is a dated check, not a guarantee against undiscovered flaws. The update is tracked in [#18](https://github.com/PinedaTec-EU/LeonardoMD/issues/18).

Mermaid is bundled from its modular `mermaid.core.mjs` entry, rather than its prebundled distribution, because that distribution carries older embedded sanitizer/math copies. The build resolves both direct and Mermaid-internal DOMPurify/KaTeX to the patched versions. Its build record in `THIRD_PARTY_SOURCES.json` includes the entry source, compiler, options, overrides and lock fingerprint. [Build package](mermaid-build-package.json) and [dependency lock](mermaid-build-lock.json) preserve the exact graph. `npm audit --omit=dev` returned zero findings for that graph on 2026-10-07.

To reproduce, copy those two JSON files to a disposable directory as `package.json` and `package-lock.json`, run `npm ci --ignore-scripts`, and check installation succeeds. Create `entry.mjs` using the recorded entry source, then run the locked esbuild executable with the recorded options and an output path inside that disposable directory. Compare its output SHA-256 with the manifest before replacing repository assets. Tests compare the actual packaged resources with their recorded hashes and exercise Mermaid's internal math with the standalone math engine disabled.

Patched-engine regression fixtures exercise Gantt with all weekdays excluded and radar with an untrusted large tick count in real WebKit. Never run these denial-of-service fixtures against an older vulnerable bundle. The same integration target validates sanitization, optional resource isolation, math, local images and PDF export.

Native visual acceptance uses `Examples/Proyecto/docs/arquitectura.md`: standalone viewer, project navigation, focus with panel restoration, split editor, optional extensions and palette controls. Author-owned screenshots are attached to the implementation PR with their source commit, viewport and state. Development findings are tracked in [#2](https://github.com/PinedaTec-EU/LeonardoMD/issues/2), [#3](https://github.com/PinedaTec-EU/LeonardoMD/issues/3), [#4](https://github.com/PinedaTec-EU/LeonardoMD/issues/4), [#5](https://github.com/PinedaTec-EU/LeonardoMD/issues/5), [#6](https://github.com/PinedaTec-EU/LeonardoMD/issues/6) and [#7](https://github.com/PinedaTec-EU/LeonardoMD/issues/7).

## Performance evidence and limits

The application emits OSLog metrics under `eu.pinedatec.LeonardoMD`: `application_window_ready`, `document_opened`, and `markdown_render_ready`. The renderer reports JavaScript Markdown duration separately from initial page load duration, so engine/resource loading is not confused with parsing.

Development fixture measurements on macOS 27 / arm64 with Swift 6.4 include document read/open times around 0.2–0.6 ms and Markdown JavaScript processing around 1–7 ms. These are small disposable fixtures, not cold-start or sustained-scroll guarantees. The PR records optimized native sample measurements for the reviewed commit.

US.000011 budgets remain targets. Sustained 60 fps, peak memory on very large documents and a multi-device performance matrix require profiling beyond this smoke validation. Disabled engines are proven absent from the resource allowlist, HTML scripts and JavaScript globals; disabling replaces and detaches the old context. This proves loading isolation, not a precise operating-system RSS release amount.

The MVP polls external file/configuration changes every two seconds, loads tree children on expansion, streams searches and debounces preview updates. Git and file operations run asynchronously. User input is protected while a document navigation is reading from disk; Git navigation stays on its initiating project until completion.
