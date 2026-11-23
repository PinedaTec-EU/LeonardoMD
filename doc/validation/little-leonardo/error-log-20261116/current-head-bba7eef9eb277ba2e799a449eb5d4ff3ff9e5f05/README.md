# Little Leonardo bilingual error evidence — 2026-11-16

This is exact-source native simulator evidence for PR #435. Product and UI-test
code source is `bba7eef9eb277ba2e799a449eb5d4ff3ff9e5f05`; PR head
`3b36f8ed7355af9caf1ac5331c8538d502373bef` added evidence only. Original
screenshots, source SHAs, capture context and image hashes are recorded in
[manifest.json](manifest.json) and the adjacent `.context.json` files.

## English

`OnDemandSyncUITests/testEnglishSharedDownloadFailureLocalizesVoiceOverCopy()`
passes 1/1 on iPhone 17 Pro / iOS 26.5. The test checks the concise alert,
English retry guidance, and that inline reference `LL-7638E7533D2C` appears in
the local downloads log.

- [Failed file and retry guidance](english-file-failure.png)
- [Inline document error](english-document-error.png)
- [Matching local log entry](english-diagnostic-log-reference.png)

## Español

`OnDemandSyncUITests/testCatalogueContextRetentionAndSeparateCache()` passes
1/1 on a new task-owned iPhone 17 Pro / iOS 26.5 simulator. It exercises the
Spanish file alert, inline preview error and local log alongside the isolated
on-demand fixture. The alert reference `LL-21D29F48CB0A` is visible in the same
log capture; the test asserts that inline reference `LL-6CE6C8324E02` matches
its log entry.

- [Ajustes de sincronización](storage-separate.png)
- [Aviso de descarga](spanish-file-failure-alert.png)
- [Error al abrir el documento](spanish-document-error.png)
- [Registro con las referencias de ambos avisos](diagnostic-log-latest.png)

The Spanish host fixture passes 1/1 with zero snapshot requests. Its audit
records catalogue metadata only, a single explicit file fetch, and the two
expected failed-download attempts; see [fixture-audit-spanish.json](fixture-audit-spanish.json),
[metadata-only.json](metadata-only.json) and [single-file.json](single-file.json).
The simulator is isolated from physical devices and uses synthetic content.

The successful fixture `swift test` invocation advanced PR #435's recorded
compiler delta from 71 to 72. The prepared simulator UI tests used
`test-without-building`. The result summaries and attachment export map remain
available beside the captures. This evidence does not establish physical-device
or large-image transfer acceptance under #380.
