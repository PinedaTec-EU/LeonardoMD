# Synchronization Preferences validation — v40

This refresh records the corrected bilingual guide captures and the fresh
packaged-app Help smoke for PR #428. The Preferences state captures for the
red/green indicator, checking stability, pairing, sharing and source-review
draft behavior remain in [v39](../428-quiet-status-v39/README.md). Their tested
product source is `9c970868ebcc53180867a12853cf9aa078b164d1`; the current PR head
adds a capture-test correction and a release-ledger entry, with no later
product-source changes.

## Bilingual component captures

The images in `user-guide/` are synthetic native WKWebView component captures
from Guide v59. Their context files retain the source SHA, locale, capture time,
viewport, operating-system report and WebKit user-agent; generated metadata
sidecars bind each original PNG to its SHA-256 and current PR checkout revision.
They are help-component evidence, not packaged-app or hosted-beta acceptance.

| Guide section | English capture | Spanish capture |
|---|---|---|
| Activation switch | [PNG](user-guide/section-activation-switch-en.png) · [context](user-guide/section-activation-switch-en.context.json) · [metadata](user-guide/section-activation-switch-en.metadata.json) | [PNG](user-guide/section-activation-switch-es.png) · [context](user-guide/section-activation-switch-es.context.json) · [metadata](user-guide/section-activation-switch-es.metadata.json) |
| Sharing and sync controls | [PNG](user-guide/section-sync-sharing-v14-en.png) · [context](user-guide/section-sync-sharing-v14-en.context.json) · [metadata](user-guide/section-sync-sharing-v14-en.metadata.json) | [PNG](user-guide/section-sync-sharing-v14-es.png) · [context](user-guide/section-sync-sharing-v14-es.context.json) · [metadata](user-guide/section-sync-sharing-v14-es.metadata.json) |
| Unavailable sync and retained review draft | [PNG](user-guide/section-sync-review-draft-unavailable-en.png) · [context](user-guide/section-sync-review-draft-unavailable-en.context.json) · [metadata](user-guide/section-sync-review-draft-unavailable-en.metadata.json) | [PNG](user-guide/section-sync-review-draft-unavailable-es.png) · [context](user-guide/section-sync-review-draft-unavailable-es.context.json) · [metadata](user-guide/section-sync-review-draft-unavailable-es.metadata.json) |

## Packaged Guide v59 Help smoke

The tested candidate was a disposable fresh process, PID `38746`, launched with
`--new-instance` from the PR worktree's `output/LeonardoMD.app`. The QA bundle
identity was `eu.pinedatec.LeonardoMD.qa.3b2e20f679d2449baaa5223131279229`;
its real `LeonardoMD` executable reported version `0.3.1333`, build `1333`, and
had no `XCTest.framework` dependency. The first app window became visible and
accessible. Product code in the bundle matches `9c970868ebcc53180867a12853cf9aa078b164d1`;
the later PR changes affect the capture assertion and ledger only. The bundle
was re-signed with its QA identity and reports `stable`; it is not a beta
archive or beta-channel acceptance.

In that same process, the bundled Spanish guide was opened through Ayuda → Guía
de Leonardo. The app interface was then switched to English, and the English
guide was opened through Help → Leonardo user guide. Both Help tabs remained
open in PID `38746`. Bundled guide hashes match the package assets and the
personal guide copies:

| Locale | Guide v59 MDLZ SHA-256 |
|---|---|
| English | `85d6d9d6d63c570f6d81cf15bb042cb93d3d13361fcbce9a1fc0050cdaa677af` |
| Spanish | `f604924347a79acf39389a0aabbedba071f2a6c723b93a37006b8480a452ec67` |

With Mermaid, Math and Charts enabled in the isolated QA profile, the English
and Spanish screens showed rendered Mermaid diagrams, inline math, one-line
and multiline display equations, the tagged box-counting equation `(1)`, charts,
tables and bundled local images. The Math source was checked for underscores
and underbraces. No KaTeX error or literal display delimiter appeared in the
enabled examples. With Math disabled in the English guide, the display source
and `$$` delimiters remained literal, while code examples and the separate
code block stayed unchanged.

The separate v1 practice form was opened from chapter 4 of each guide, filled,
saved, closed and reopened through the guide action. Both reopened forms showed
their three synthetic answers and the local-saved status. The isolated response
files validate with the bundled MDLR validator as v1 forms with three fields
and three values:

| Locale | Reopened form capture | Response SHA-256 |
|---|---|---|
| English | [PNG](packaged-smoke/en-practice-reopened.png) · [context](packaged-smoke/en-practice-reopened.context.json) · [metadata](packaged-smoke/en-practice-reopened.metadata.json) | `4396a5d8d278da7519c36f58e93eb82be796cb14e8312fa702064397e9d2c86e` |
| Spanish | [PNG](packaged-smoke/es-practice-reopened.png) · [context](packaged-smoke/es-practice-reopened.context.json) · [metadata](packaged-smoke/es-practice-reopened.metadata.json) | `77b719ad46f3d44a5ab515a1e2b9923902197bbfc2c3b6e0eb1724ff89c6ceb8` |

No owner guide, practice response or preference file was used: the app ran with
the disposable `CFFIXED_USER_HOME` at
`/tmp/LeonardoMD-QA-428-es-v59-home`. Math, Mermaid and Vega-Lite/Charts were
enabled again at the end of the check. After capturing and hashing the reopened
forms, candidate PID `38746` was closed and its QA bundle and isolated profile
were moved to Trash. The original owner data was not used or changed.

## Packaged screenshot inventory

The nine original window captures below are synthetic. Each adjacent context
and generated metadata sidecar records the route, observed WKWebView user-agent,
capture time, `1260×850` app viewport, `2520×1700` pixel image, `viewport` mode
and SHA-256. See the sidecar for the full state and source-revision indicators.

| Evidence | PNG | Context / metadata | Capture time (UTC) | Image SHA-256 |
|---|---|---|---|---|
| English Math enabled | [PNG](packaged-smoke/en-math-enabled.png) | [context](packaged-smoke/en-math-enabled.context.json) · [metadata](packaged-smoke/en-math-enabled.metadata.json) | 2026-11-12 19:50:17 | `e01064582ec328cb9cc703b202af1449c498f22b2c9de489f7c61264209276df` |
| English Math fallback | [PNG](packaged-smoke/en-math-disabled-fallback.png) | [context](packaged-smoke/en-math-disabled-fallback.context.json) · [metadata](packaged-smoke/en-math-disabled-fallback.metadata.json) | 2026-11-12 19:52:23 | `38071029ab9bcc368fbc3486d2e4830a741ed678b58d51767ed6419e557d24bd` |
| English Mermaid and inline math | [PNG](packaged-smoke/en-mermaid-inline-math.png) | [context](packaged-smoke/en-mermaid-inline-math.context.json) · [metadata](packaged-smoke/en-mermaid-inline-math.metadata.json) | 2026-11-12 19:49:48 | `caa4a1d66e1ffb7676ed5412eca38e2a84ec9c0b91ae57d76d26c8529496876c` |
| English table and local image | [PNG](packaged-smoke/en-table-local-image.png) | [context](packaged-smoke/en-table-local-image.context.json) · [metadata](packaged-smoke/en-table-local-image.metadata.json) | 2026-11-12 19:51:49 | `e67d03e983144e6c7f4deba78b631491b8181f7bbcb062e9805e388f9ccda878` |
| Spanish Math enabled | [PNG](packaged-smoke/es-math-enabled.png) | [context](packaged-smoke/es-math-enabled.context.json) · [metadata](packaged-smoke/es-math-enabled.metadata.json) | 2026-11-12 19:54:29 | `279082b6b24b747eaefdafcea7dd7886818db80518895192a142557c32846e10` |
| Spanish Mermaid and inline math | [PNG](packaged-smoke/es-mermaid-inline-math.png) | [context](packaged-smoke/es-mermaid-inline-math.context.json) · [metadata](packaged-smoke/es-mermaid-inline-math.metadata.json) | 2026-11-12 19:54:50 | `6efefc66f79aa4008f49618a1fd9cbd35d0e86ceb38109bea7607ff76431db33` |
| Spanish table and local image | [PNG](packaged-smoke/es-table-local-image.png) | [context](packaged-smoke/es-table-local-image.context.json) · [metadata](packaged-smoke/es-table-local-image.metadata.json) | 2026-11-12 19:55:09 | `4f6628b74be8ad61dc140a3044aec187143324a412bdb1908d1aad6d100885cf` |
| English practice form reopened | [PNG](packaged-smoke/en-practice-reopened.png) | [context](packaged-smoke/en-practice-reopened.context.json) · [metadata](packaged-smoke/en-practice-reopened.metadata.json) | 2026-11-12 20:05:21 | `3595874977f3fa518b95a36fe37ce58e8588642b8b0077925050eeaecc32d0e2` |
| Spanish practice form reopened | [PNG](packaged-smoke/es-practice-reopened.png) | [context](packaged-smoke/es-practice-reopened.context.json) · [metadata](packaged-smoke/es-practice-reopened.metadata.json) | 2026-11-12 20:00:43 | `d858de1d6fc80e28d426a07fab32ec9dc9af06aa3bc061fbcfe1f4ffe68741ae` |

## Limits

This completes packaged Help and practice acceptance for the local QA build.
It does not establish a live registered-helper failure/recovery run or hosted
beta update, install and relaunch acceptance. Those hosted checks remain after
publication; no beta publication or issue closure is claimed here.
