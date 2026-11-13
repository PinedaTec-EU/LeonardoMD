# LeonardoMD agent context

Read [current state](current-state.md), then the relevant source target. Human product requirements live in `doc/US`, not here.

- [System overview](system-overview.md)
- [Project identity across macOS and iOS](project-identities.md)
- [Open questions](open-questions.md)
- [Change log](log.md)

- [Updates](updates.md)

- [Table layout](table-layout.md)

- [Open Leonardo documents and agent plugins](leonardo-format.md)

- [Native release notes](release-notes.md)

- [Document Undo and Redo](document-undo.md)
- [Find in open documents](document-search.md) — window-scoped literal/regex search, tab navigation and source-only highlights.

- [Mobile Git architecture reevaluation](../doc/adr/0002-reevaluate-mobile-git-engine.md) — owner-selected iOS read-only and macOS/Windows desktop-sync direction; runtime migration pending.
- [Local image resource policy](image-resources.md)
- [PDF export and preview replacement](pdf-export.md)

- [Optional document extensions](document-extensions.md)

- [Page objects and visual rubrics](page-objects.md)
- [macOS rubric capture](rubric-capture.md) — owner-side helper/XPC request, review, safe save and document identity guard for [#341](https://github.com/PinedaTec-EU/LeonardoMD/issues/341).
- [Rubric exchange protocol](../doc/mobile/rubric-exchange.md) — authenticated, targeted Mac↔iOS rubric requests, capture-only mobile response flow and durable retry boundaries; physical distribution remains separate.

- [On-demand synchronization and cache](on-demand-sync.md)
- [Desktop peer synchronization](desktop-peer-sync.md) — keep revoked-device recovery distinct from a removed project grant.
- [HTTPS response lifetime and physical acceptance](https-response-lifetime.md)
- [Little Leonardo Classic UI and rotating canvas](mobile-classic.md)

- [Background helper upgrade](helper-upgrade.md) — launch identity, safe renewal and persistent consent fencing for #412.
