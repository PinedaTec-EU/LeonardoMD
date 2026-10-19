# Markdown to MDLF migration validation

Tracking: [#191](https://github.com/PinedaTec-EU/LeonardoMD/issues/191),
implementation [PR #192](https://github.com/PinedaTec-EU/LeonardoMD/pull/192).

## Regression boundaries

- Core conversion retains the complete front matter envelope, including unknown
  YAML structures and comments, under `values.markdownFrontMatter`. LF/CRLF,
  alternate closing delimiters, EOF after the delimiter, empty bodies, missing
  envelopes and unclosed envelopes are covered. The latest prose is compared as
  UTF-8 bytes and round-tripped through the actual MDLF parser/serializer.
- AppSession migration saves the latest draft and retains the original `.md`.
  Existing tests cover disguised MDLF, unsupported versions, exclusive destination
  creation, conflicts, authorization and pending preview edits.
- Render payloads expose original metadata and tags; native MDLF without migrated
  metadata uses its document title. Standard Markdown remains isolated.
- `WebKitRuntimeTests.testMigratedMarkdownRendersMetadataOutsideEditedArticle`
  renders a synthetic document in the real native WKWebView. It checks the edited
  article, author, URL and tags, excludes internal JSON from metadata, then hides
  metadata and verifies that tags remain. The test harness is 1000×800 points.

## Visual evidence

CI runs the WebKit test with `LEONARDO_VISUAL_EVIDENCE` and uploads the exact-head
`preview-tags-<SHA>` artifact. The migration captures are
`mdlf-migration-metadata.png` and `mdlf-migration-hidden-metadata.png`. The workflow
records the SHA and viewport in `provenance.txt`. These are native test-hosted
components, not evidence of a fresh packaged application launch.

## Local document repair

The owner-authorized repair preserved the saved MDLF prose and original YAML
byte for byte, retained a complete adjacent backup before replacement, validated
against the bundled v1 schema, and left the source `.md` unchanged. Evidence and
hashes are on the canonical issue. The running installed 0.1.441 instance reloaded
the repaired document. Its old metadata panel still requires the corrected app;
this task does not claim an app installation or beta/stable publication.
