# PR #428 synchronization correction captures

These native `NSHostingView` captures use isolated synthetic devices, proposals
and status. The state screenshots and their `.context.json` / `.metadata.json`
sidecars are retained as originals. Capture time, locale, screen, native-point
viewport, image pixels, SHA-256 and source revision are recorded per image.

The preference status and sharing-row captures were rendered from product UI
source `f61934426119d2fb16e28bd8c84deb900e995e25`. The bilingual action-capture
fixture was committed separately as `8927d506a8d0f9c5f2fdf94500c920bffa5b1d7e`;
it adds the English/Spanish test capture loop and the PR compilation ledger.
The review-row illustration was then recaptured at native 1× scale to stay
within the guide's existing image budget. No sync preference implementation
changed after the product source SHA.

| State | Captures |
| --- | --- |
| Confirmed error held through retry and recovery | `status-recovery-error.png`, `status-recovery-checking.png`, `status-recovery-online.png` |
| Confirmed healthy status and transient check | `status-online.png`, `status-checking.png` |
| Approval presentation before and after a helper check | `status-approval-before.png`, `status-approval-required.png` |
| Shared project before, during and after retry | `project-before.png`, `project-retrying.png`, `project-recovered.png` |
| Incoming review action disabled during helper failure | `incoming-review-unavailable-en.png`, `incoming-review-unavailable-es.png` |
| Pairing approval action disabled during helper failure | `consent-actions-unavailable-en.png`, `consent-actions-unavailable-es.png` |
| Paired device retained with local sharing off while revoke is disabled | `paired-device-sharing-off-en.png`, `paired-device-sharing-off-es.png` |

The new English and Spanish images are also used in chapter 14 as
`sync-review-unavailable.png`. They show only a production component with
synthetic state. They do not claim that Help opened in a fresh packaged process,
that a signed helper was live, or that a beta installed and relaunched.

The matching PR #428 run of `SyncHelperControllerTests` passed 118 tests with
one opt-in capture test skipped and no failures. The output was generated with
`LEONARDO_SYNC_STATUS_EVIDENCE` and `EVIDENCE_SHA=f61934426119d2fb16e28bd8c84deb900e995e25`.
