# Separate guide practice: native interaction evidence

Capture/build source: `ead1cd92b0de4c70b65363ba65c6abf200919c6d`. Four original PNGs and canonical sidecars were
collected from that clean checkout. Later evidence-only commits change only
`doc/validation/guide-practice/`; Sources, Tests, resources, scripts and Swift
package inputs must remain identical for this mapping to apply.

Actual production DocumentTabsView/WorkspaceView and WKWebView, using temporary
preferences and synthetic data. Screens are element snapshots, not full-page
captures. The form continues below the measured viewport where cropped; tests
check that all three controls are enabled. WKWebView reports the compatibility
User-Agent in every sidecar (not an inferred host OS/browser version).

Observed: the real document link is clicked through the renderer; another tab
opens in Fill mode with the source protected; Ada is entered through DOM input
and saved. The guide and unrelated draft stay unchanged. Repeating the action
selects the existing form and restores Fill mode; closing/reopening retains Ada.
Both locales pass. Separate tests reject untrusted, stale/inactive, busy and
crafted requests. Generic renderer engines and normal navigation remain intact.

| Original / provenance | Screen/state | Viewport / image | UTC capture start | SHA-256 |
| --- | --- | --- | --- | --- |
| [action-en](action-en.png) · [sidecar](action-en.metadata.json) · [context](action-en.context.json) | /native/user-guide/en; Guide chapter 4; reading mode; fixed practice link; no form fields; language en | 1100×688 CSS; 2200×1376 pixels | 2026-11-01T07:29:18.222000+00:00 | `1e10a31e4b048a977962a930a5c760709e610e42a9e840710a3236f3b22342a6` |
| [action-es](action-es.png) · [sidecar](action-es.metadata.json) · [context](action-es.context.json) | /native/user-guide/es; Guide chapter 4; reading mode; fixed practice link; no form fields; language es | 1100×571 CSS; 2200×1142 pixels | 2026-11-01T07:29:19.922000+00:00 | `fe15a099aa8b03197d139bd77bbb56e780fe7bef33b2ff08407cebed743f5346` |
| [form-en](form-en.png) · [sidecar](form-en.metadata.json) · [context](form-en.context.json) | /native/user-guide/en; Separate practice tab; Fill form; protected structure; synthetic saved Ada answer; language en | 1100×646 CSS; 2200×1292 pixels | 2026-11-01T07:29:18.945000+00:00 | `d69dfb154b830b03f1d05033d690b819db6d3ffb082903d16a04b8f36880343f` |
| [form-es](form-es.png) · [sidecar](form-es.metadata.json) · [context](form-es.context.json) | /native/user-guide/es; Separate practice tab; Fill form; protected structure; synthetic saved Ada answer; language es | 1100×387 CSS; 2200×774 pixels | 2026-11-01T07:29:20.671000+00:00 | `de6d60c48f9515b353584efcf625e52a7714ea87a1ee6001499a402b4d49a34d` |

Reproduce after building current tests with the repository compilation recorder:

```sh
LEONARDO_GUIDE_PRACTICE_EVIDENCE=/tmp/guide-practice swift test --skip-build --filter GuidePracticeNavigationTests
```

Set EVIDENCE_SHA to the real source revision when collecting. Generate sidecars
with the shared capture-metadata helper before editing the checkout. This is
native component interaction evidence, not fresh packaged-process startup,
installation, beta publication or user acceptance. No user application was
terminated. Historical v4 guide captures remain in their original directory.
