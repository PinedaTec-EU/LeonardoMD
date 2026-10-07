# Changes

- 2026-10-07: Initial native macOS implementation under [issue #1](https://github.com/PinedaTec-EU/LeonardoMD/issues/1). Added standalone viewer and focus story, offline opt-in engines, and premium controls. Native QA registered [bug #2](https://github.com/PinedaTec-EU/LeonardoMD/issues/2) for missing Mermaid labels and [bug #3](https://github.com/PinedaTec-EU/LeonardoMD/issues/3) for relative images; corrections and final evidence remain part of the same PR.

- 2026-10-07: [#25](https://github.com/PinedaTec-EU/LeonardoMD/issues/25) closes symlink search escapes and target mutations with explicit omission/rejection policy and actual link fixtures; [#26](https://github.com/PinedaTec-EU/LeonardoMD/issues/26) requires confirmation before document-authored local links activate system handlers. ADR/validation and this memory record the policies. [#9](https://github.com/PinedaTec-EU/LeonardoMD/issues/9) remains open for the mouse/accessibility discrepancy despite a passing fresh-process keyboard flow.
- 2026-10-07: #15 adds Sparkle menu checks and signed release preparation, tracked by https://github.com/PinedaTec-EU/LeonardoMD/issues/15.
- 2026-10-07: Added the approved pencil-lettered About banner, reusable native About window and runtime bundle version display for [#27](https://github.com/PinedaTec-EU/LeonardoMD/issues/27), initially stacked on MVP PR #8 and now integrated through PR #28.
- 2026-10-07: Added per-session document tabs, local Markdown drops, header location actions and cross-tab close/file-operation protection for [#19](https://github.com/PinedaTec-EU/LeonardoMD/issues/19), initially stacked on #8, now targeting main. Independent native view ownership preserves editor undo and reading position without copying document state between tabs.

- 2026-10-07: Refreshed #19 on main with #27/#31 integrated. Added actual native URL-provider regression coverage and constrained sidebar relocation to project-owned sources; document drops remain non-destructive.

- 2026-10-07: Added single-instance ownership, acknowledged launch forwarding and external document tab routing for [#22](https://github.com/PinedaTec-EU/LeonardoMD/issues/22), now targeting main after #21 integration. Native QA covers repeated and simultaneous executable launches plus Launch Services reopen/open-document events.


- 2026-10-07: Single-instance integration exposed a Git output completion race in hosted CI. [#35](https://github.com/PinedaTec-EU/LeonardoMD/issues/35) drains both subprocess streams through EOF before returning, with short/large-output and failed-launch regressions.

- 2026-10-08: Revalidated [#9](https://github.com/PinedaTec-EU/LeonardoMD/issues/9) and [#31](https://github.com/PinedaTec-EU/LeonardoMD/issues/31) on 0.1.0 build 1 (`041c63b`) and closed both as no longer reproduced in the tested context. Corrected project root alias handling for [#33](https://github.com/PinedaTec-EU/LeonardoMD/issues/33), preserving symlink-component checks.
