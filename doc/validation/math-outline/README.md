# Extensible math and outline navigation validation

Tracking: [#274](https://github.com/PinedaTec-EU/LeonardoMD/issues/274) and
[#364](https://github.com/PinedaTec-EU/LeonardoMD/issues/364), delivered together in
[PR #377](https://github.com/PinedaTec-EU/LeonardoMD/pull/377).

## Current candidate

All current acceptance captures use source
`4ba13fe895a80cfe9dc3a791deab321b56003d67`, guide revision 18 and the
unmaterialized application baseline 0.3.1010. The final review head may add only
this evidence directory and PR 377's recorded compilation count. Run
`python3 doc/validation/math-outline/verify-source-mapping.py <reviewed-SHA>`
to verify every other tracked product/build/test/guide/workflow input and every
original image hash. Use the reviewed source SHA, not a later version
materialization.

| Capture | CSS viewport | Image pixels | Evidence |
| --- | --- | --- | --- |
| component-en | 1100×772 | 2200×1544 | [Original](component-en.png) · [sidecar](component-en.metadata.json) · [context](component-en.context.json) |
| component-es | 1100×772 | 2200×1544 | [Original](component-es.png) · [sidecar](component-es.metadata.json) · [context](component-es.context.json) |
| packaged-en | Unavailable via native CUA | 2520×1700 | [Original](packaged-en.jpg) · [sidecar](packaged-en.metadata.json) · [context](packaged-en.context.json) |
| packaged-es | Unavailable via native CUA | 5120×2818 | [Original](packaged-es.jpg) · [sidecar](packaged-es.metadata.json) · [context](packaged-es.context.json) |

Canonical helper sidecars bind original bytes to dimensions, hashes and observed
capture time. Component context contains the actual WKWebView User-Agent
(compatibility-version report), measured CSS viewport and native capture size.
Native CUA does not expose the packaged browser version or CSS viewport; these
fields are explicitly null rather than inferred from image size. No original
image was resized, cropped or annotated.

Both component captures show complete brace curves, radical, extensible arrow,
cancellation stroke and equation tag. The packaged captures show the same
examples after selecting their actual outline entry. Synthetic guide content
contains no personal document values. AX observations redact the owner path and
normalize trailing whitespace; original captures remain unchanged. Practice
observations retain only the fictional field/status rows.

## Actual packaged process

`native-qa.json` records fresh PID 11832, the exact QA bundle identity and
executable hash, real executable/dependency checks, both guide archive hashes
and candidate/bundle/personal-copy equality. `./launch.sh --qa` created the
bundle after the previous QA quit normally; a new process and actual first
window were observed. This is ad-hoc QA, not signed distribution acceptance.

Observed in that same process:

- Help opened both localized revision-18 guides; each personal archive exactly
  matched its candidate resource before testing.
- Preview showed every characteristic math shape and tag. Turning Math off in
  each language preserved literal notation; recommendations were dismissed
  without changing persistent suppression, then the original Math=true returned.
- Outline selection brought the selected heading to the preview start.
  Selecting it after scrolling returned to the same target; Split retained the
  exact preview target while the editor selected the corresponding source line.
- English and Spanish practices accepted fictional names, saved, closed and
  reopened with those names. Original blank names were restored and saved.
- Original English language returned. The observed Leonardo Classic/Parchment
  appearance and other preferences were retained.

## Validation examined

The final revision-18 local suite passed 699 XCTest cases (35 skipped), no
failures, plus 70 Swift Testing cases. The focused renderer/controller/help/
Split suite passed 16 cases; deterministic guide packaging passed 3 cases.
Current-head CI remains authoritative for full final-head checks.

Tests cover generated SVG geometry and namespace/bounds, active-content and
external SVG-reference rejection, unchanged raw-document SVG rejection, CRLF
and front-matter line offsets, repeated/formatted headings, Setext/raw HTML,
forged heading metadata, fenced source, early/latest navigation requests,
replacement, refresh and controlled in-flight extension rendering. The latter
reproduced premature scrolling before the readiness correction, then passed.

## Reproduce the local native check

1. Check out the reviewed head in an isolated worktree and run the source/hash
   verifier above; continue only after it succeeds.
2. Follow AGENTS.md's single-instance/owner-quit contract, then run
   `LEONARDO_SOURCE_PR=377 ./launch.sh --qa`. Confirm the real executable,
   dependencies, new PID and first window before claiming startup.
3. Open Help in English and Spanish. Verify candidate/bundled/personal guide
   content identity. Select the math regression heading in the outline, repeat
   after scrolling, and test Split. Check enabled shapes and disabled literals.
4. Fill each practice with fictional data, save/close/reopen, then restore the
   original values and preferences. Capture original windows and observed
   context. Reviewer scratch images do not replace author-owned evidence.

## Separate diagnostic findings

- [#378](https://github.com/PinedaTec-EU/LeonardoMD/issues/378): concurrent QA
  branches had allocated different guide contents as v17. The preserved
  personal v17 copy did not match the first candidate. The historical
  [diagnostic image](diagnostics/cached-guide-v17.jpg) and its sidecar identify
  source `e55a1c3…`, PID 97984 and the stale-copy state. It is **not** current
  Help acceptance evidence. This PR uses unused v18 and adds the content-identity
  QA check; general candidate-scoped copy isolation remains open.
- [#379](https://github.com/PinedaTec-EU/LeonardoMD/issues/379): a very long
  tagged equation can overlap its number in a narrow Split pane. The current
  [diagnostic image](diagnostics/narrow-split-tag.jpg) records that separate
  layout problem. Preview/wider-window rendering is readable; this PR changes
  no layout stylesheet. SVG geometry and outline destination are independently
  verified. A general narrow-layout correction is outside these two fixes.

Earlier `doc/validation/display-math/` evidence belongs to accepted PR #363 and
its older guide/source identity; it does not substitute for these captures.
