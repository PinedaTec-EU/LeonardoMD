# Leonardo document validation

Tracking: [#167](https://github.com/PinedaTec-EU/LeonardoMD/issues/167), [PR #168](https://github.com/PinedaTec-EU/LeonardoMD/pull/168).

## Reproduction

Use the source PR compilation recorder for every successful compiling command:

```sh
LEONARDO_VISUAL_EVIDENCE="$PWD/output/format-evidence" python3 scripts/compile-and-record.py --pr-number 168 -- swift test
```

The new native fixture `LeonardoFormatVisualTests` hosts the actual `WorkspaceView` and form inspector at 1260 × 850 points. It captures local MDLF, package mode and extracted-folder mode in English and Spanish. `WebKitRuntimeTests` exercises the real renderer, field values as literal text, code exclusion, rich-to-standard context changes, background loading, table sizing and legacy-comment exclusion in MDLF.

This is native XCTest/view-hosting and real WebKit evidence, not an image mockup. It does not start a standalone XCTest application. The owner's installed LeonardoMD process remains running; fresh packaged-process/first-window startup has not been established for this change.

## Automated scope

- Core: explicit format/version, unknown-key rejection, partial layout defaults, canonical examples, opaque body/CRLF preservation, typed draft/submission validation, dates, custom messages and bounded regular-expression execution.
- Transport: conventional stored/DEFLATE ZIP interoperability, checksums and unsafe/duplicate paths, extraction ownership, original-file preservation, external-change conflicts, repeated saves, renamed packages, asset-reference rewriting, code/answer exclusion and local-image containment.
- Application: standard Markdown detection, form initial modes/field persistence, migration conflicts and pending preview edits, authorization denial without writes, package saving, drag policy and native chrome states.
- Plugin: Python CLI transport regressions, portable/host manifests, bundled schema identity and authoring instructions. `claude plugin validate ./plugins/leonardo-format` checks the Claude manifest.
- Both public example documents validate with `mdlz.py validate <document>`. The dependency-free helper always applies its bundled canonical schema, including to the root document before archive inspect, extraction or packing; `--schema` adds an external constraint without relaxing the canonical schema.

A save/export decision selects its output format before showing the save panel. Extracted documents show the actual MDLF/MDLR filename and require export to create a new package.

Response selection and package collection share one Core resource scanner. Regression tests cover HTML and reference-style images, relocated exported packages, source-byte preservation, and code examples that must not be treated as resources.

Final command results and exact reviewed SHA are recorded on the PR; the source documentation does not assert release publication.

Hosted WebKit regression: [#169](https://github.com/PinedaTec-EU/LeonardoMD/issues/169) records the remote-only background readiness timeout. Background images explicitly use eager loading before their source is assigned; real WebKit asserts that policy. The old source-string assertion for unconditional lazy loading was replaced by the runtime behavior check. Plugin tests also run in the normal macOS CI workflow.

The follow-up runner diagnostics showed both SVG images complete with positive raster widths (950 and 400), rather than the 20 reported locally. Readiness therefore checks successful decoding, while separate assertions check the declared geometry and eager-background policy; it does not assume identical WebKit SVG raster dimensions.

`SessionRenderingPackageAssetTests` opens packaged and extracted documents while
an active project contains conflicting assets with the same names. It verifies
the workspace asset root and real WebKit preview/PDF export. With the evidence
environment above it writes `package-assets/package.png`, `extracted.png` and
`capture-context.txt` (800 × 600 points) alongside the other captures.

Native and plugin validation consume the same acceptance/rejection corpus in
`Tests/FormatContractFixtures`. Tests check schema copy identity, definition and
layout safety, portable patterns, opaque invalid draft answers, Unicode archive
collisions and the shared 64 MiB archive / 32 MiB expansion limits.

Secure-extraction regressions cover exclusive destination claims against files, symlinks and directories; retargeted parent/child paths; ownership-aware failure cleanup and temporary discard; and path/directory expansion limits. The tests use per-call scheduling hooks, with no shared mutable race state. Plugin extraction fails before effects on hosts without descriptor-relative no-follow support; read/validation/packing remain available.

PR capture tests prefer `EVIDENCE_SHA`, set to the checked-out pull-request head by CI, over the event's synthetic merge SHA. Directory-alias regressions include distinct NFC/NFD spellings of a shared parent, in addition to case folding.
