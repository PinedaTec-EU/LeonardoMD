# Integrated-fixes validation — PR #383

The candidate includes #377 (`d4ca398e85f949c83d623bdf3b2bee0bacb94909`), which closes #274 and #364, and its materialized baseline 0.3.1045. Both bundled guides use revision 22; earlier personal copies remain intact.

## iOS application

Real `LittleLeonardo.app` built from `68b077e47beb3cc5aecb4d901db264a9ac0e280f`; iPhone 17 Pro simulator, iOS 27.0 (24A434), task-owned device `D1B54EA2-B8EF-4DB6-8D49-AEFE06FA924E`. [Machine-readable result](ios-test-summary.json): **14 passed, no failures or skips** (12 unit tests and 2 UI tests).

The English walkthrough resets the demo, confirms empty answers, opens field help, fills and saves a fictional name, then terminates/relaunches and verifies persistence. The Spanish walkthrough resets independently, fills/saves, inspects the Leonardo source with separate `values`, returns to preview, edits again, saves and verifies the exact edited value after another relaunch. The test does not assume a particular insertion caret position.

Original XCTest attachments and adjacent native provenance sidecars:

- [English welcome](english-welcome.png), [Spanish welcome](spanish-welcome.png).
- [Markdown and table](english-gallery-0.png), [local image and Mermaid](english-gallery-1.png).
- [Actual inline/display math, underbrace, tag (1), chart](english-gallery-2.png).
- [Form fields](english-gallery-3.png), [saved English practice](english-saved-practice.png).
- [Spanish source](spanish-source-with-saved-values.png), [Spanish persisted practice after source](spanish-persisted-practice-after-source.png).

Manual inspection confirms the image, diagram, underbrace shape, equations/tag, chart and real fields. Native XCTest exposes neither a browser version nor a CSS viewport; metadata records that limitation and actual image dimensions/hashes rather than fabricating browser-only fields. Local Debug distribution version fields are absent; the full source SHA identifies this artifact.

## Other checks

- Refreshed full SwiftPM: **366 XCTest cases, 30 skipped, no failures**, plus **28 Swift Testing cases passed**. Source `28bc6eb`; subsequent product changes consist only of the materialized version/notes baseline. CI revalidates the final head.
- Bundled guide components: **5 passed**. Python tools: **111 cases, 7 skipped**; portable format: **38 passed**; packaging: **20 passed**; deterministic guide generation: **3 passed**. Both demo MDLR resources pass the canonical v1 schema.
- Ten successful compiler-bearing invocations currently allocated in this PR's ledger. The failed caret-assumption test invocation is excluded. A later QA compilation must advance this count before final review.

## Pending native acceptance

The macOS GUI turn is reserved for #377's official beta acceptance. No LeonardoMD instance or common preferences/copies are being changed by this thread while it owns that turn. After explicit release, a fresh packaged candidate must open both Help guides, verify template/personal-copy hashes, enabled rendering, outline destination, disabled/code fallback and separate practice fill/save/reopen. This PR remains draft until that acceptance, final exact-head CI and a fresh strict independent judge pass.

No App Store/TestFlight upload, physical-device or airplane-mode exercise is claimed. Demo resources are bundled and no pairing/account/network is required; synchronized projects remain read-only and separate from demo storage.
