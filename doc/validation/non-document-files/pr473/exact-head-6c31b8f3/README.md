# PR #473 — current Little Leonardo UI evidence

The screenshots were captured in the successful focused XCUITest run
`.build/qa-pr473-corrections-20261119-run5.xcresult` on the task-owned iPhone 17
simulator (`LittleLeonardo PR473 QA 20261119`, iOS 27.0,
`4C448AE1-1736-4047-BCC1-0F9B3CA82182`). The app code used by that run matches
commit `6c31b8f3d054779f0dd917b67d21e36a57bfc797`; the subsequent evidence-only
commit adds these images and metadata. The test block passed 6/6, including the
read-only MDLF/MDLR reader, localized recovery copy in both languages, default
off preference persistence, and recovery export without publishing.

These are native iOS screenshots; no browser is involved. The recovery captures
are 1206 × 2622 pixels at 3×, with a 402 × 874 point viewport. The MDLR reader
snapshot is 1206 × 2172 pixels at 3×, with a 402 × 724 point viewport. All data
is synthetic. Each metadata sidecar records the observed capture time, state,
device, source revision and image hash.

| State | Screenshot | Metadata |
| --- | --- | --- |
| English legacy recovery explanation and export action | [ios-recovery-copy-en.png](ios-recovery-copy-en.png) | [ios-recovery-copy-en.metadata.json](ios-recovery-copy-en.metadata.json) |
| Spanish legacy recovery explanation and export action | [ios-recovery-copy-es.png](ios-recovery-copy-es.png) | [ios-recovery-copy-es.metadata.json](ios-recovery-copy-es.metadata.json) |
| Filled MDLR rendered as read-only document content | [ios-mdlr-preview.png](ios-mdlr-preview.png) | [ios-mdlr-preview.metadata.json](ios-mdlr-preview.metadata.json) |

The same test invocation also asserted that received MDLF and MDLR documents
render through the Leonardo-aware reader and that MDLR form controls are
disabled. Current screenshots for the desktop preference and the received
MDLF screen remain in the earlier [capture record](../exact-head-041c4faa/README.md);
the #489–#492 follow-up does not change those screens.
