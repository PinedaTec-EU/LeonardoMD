# PR #610 browser preview captures

The implementation agent captured these original Chromium viewports against
source `7b8a3a9a3bb2665ce625999c495cb2860b15aa5d`, exported directly from Git.
The controlled loopback worker used this exact plugin and exact packed renderer.
The viewport was 1280 × 900 CSS pixels at device pixel ratio 1. The sidecars
record the observed browser, route with the capability removed, scope,
timestamp, source identity, fixture and image hashes, and browser/worker
teardown. No product input differs between this evidence branch and the PR.

| Capture | State |
| --- | --- |
| [MDLF](mdlf.png) | Synthetic invoice, rendered table and referenced local letterhead. |
| [MDLR](mdlr.png) | Synthetic service request with saved answers, rendered read-only. |
| [MDLZ](mdlz.png) | Packaged synthetic invoice, rendered table and avatar-free bundled letterhead. |
| [Guide v166 EN](guide-v166-en-codex.png) | Exact packaged English help content, positioned at the Codex local-preview instructions. |
| [Guide v166 ES](guide-v166-es-codex.png) | Exact packaged Spanish help content, positioned at the corresponding instructions. |

To reproduce the preview on a supported installation, enable Leonardo Sync
with a supported Python runtime and use the installed plugin's documented
Browser preview flow for a synthetic local document. Open the returned URL
in a browser. For the guide states, open the bundled Guide v166 file of the
corresponding language and scroll to the local Codex preview subsection.

These captures show the browser renderer. The [separate native Help result](https://github.com/PinedaTec-EU/LeonardoMD/pull/610#issuecomment-7191822671)
records the Help and Ayuda menu routes, package hashes and process teardown.
The guide source bytes in that result match the documents captured here.
This PR changes the guide content and leaves the application Help UI route
and presentation logic in place. The installed-helper launch-service and
trusted Stop-hook rollout checks remain Beta follow-up.
