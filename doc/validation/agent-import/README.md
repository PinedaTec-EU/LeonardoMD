# Agent import guide validation

Tracking: [#329](https://github.com/PinedaTec-EU/LeonardoMD/issues/329).

The original PNGs show the production WorkspaceView / WKWebView components,
opened through DocumentTabs in both languages. The diagram is explicitly an
illustration. No PDF, external agent or account is involved in these captures.

Build/capture source: `4c300ea` (full SHA in each context sidecar). The evidence
commit adds only these observations and the second successful compilation
allocation; application, resource, test and packaging inputs are unchanged.
The metadata helper observes that allocation as a tracked dirty file; it does
not mean the screenshots were built from different application sources.

`swift test` passed for the implementation; after final copy/layout refinements,
`swift test --filter BundledUserGuideTests` passed all five native checks:
both menu translations, package/copy preservation, opening/deduplication without
replacing documents, and rendering both main and standalone guides. Python
packaging tests verify deterministic generated resources and that standalone
content derives from the main-help chapter.

This is component/test-runner evidence, not fresh packaged-process startup
acceptance. An existing user instance `/Applications/LeonardoMD.app` was running
(PID 27634); it was left untouched. No standalone XCTest executable was launched
as an application. CI separately builds and inspects the real app package.

Each PNG has its original capture context and shared-helper metadata (time,
source, measured viewport, image dimensions/hash and engine User-Agent).
