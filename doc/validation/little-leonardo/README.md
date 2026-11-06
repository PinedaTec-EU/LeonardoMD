# Little Leonardo native validation

## Current rubric capture evidence

The [current source-bound manifest](ios-rubric-capture-final-20261106-8488e9d.json) identifies source `8488e9d42ee148955ea652fc052254d2aaf3ed8b`, 40 relevant code/test/config/package input hashes, five iOS captures and two bilingual Mac consent captures. Three current native modes and nine focused iOS cases pass without failures or skips. The happy mode now waits for actual dark ink in the drawing and Preview before exporting raw screenshots, and checks their relative ink density. Earlier blank Preview attachments were premature composition captures; they do not establish a lost drawing or a renderer defect. Historical raw images remain unchanged.

The full host checkpoint passes 691 XCTest cases (656 passed, 35 optional skips) plus 70 Swift Testing cases across nine suites. Later iOS capture-readiness and Mac capture-metadata changes do not alter host production inputs; the current Mac-consent capture test independently passes. English and Spanish consent explain capture without project access; native component captures show zero projects and the unconfirmed comparison-code gate. Existing Guide v15 bytes are unchanged; five guide cases pass in the full host run and prior Python packaging checks remain bound to unchanged packages. Simulator/native-component evidence does not deliver TestFlight or physical Mac/iPhone acceptance, which remains open in #342/#343.


Historical Git implementation evidence: proprietary mobile Git is retired by [#249](https://github.com/PinedaTec-EU/LeonardoMD/issues/249). Use [retirement validation](../git-retirement/README.md) for current behavior. Git fixture reproduction below requires its recorded historical source checkpoint; removed targets are not available on the retirement branch.

These are actual native view/Simulator captures from implementation-owned fixtures, not mockups. No personal document or credential appears. Owning delivery: [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92), [#101](https://github.com/PinedaTec-EU/LeonardoMD/issues/101), [PR #93](https://github.com/PinedaTec-EU/LeonardoMD/pull/93).

## Desktop captures

Captured on 2026-10-09 from compile delta184 (desktop production/view sources unchanged through the subsequent ledger, SSH test-fixture and mobile editor corrections), using ten passing optional native controller/component tests. `NativeViewCaptureSupport` hosts real SwiftUI/AppKit views and reapplies final capture geometry. The owner app remains running independently. Git review uses an actual scoped publication/controller fixture; wakeup badge uses an actual authenticated HTTPS notification persisted before acknowledgement. Remaining layouts use isolated synthetic component state.

- Git review: 960×700 points, EN/ES, project/device/commit/base/scope identity, all four decision labels visible, application disabled until a choice.
- Git notification: 1260×850, Spanish workspace, persisted inbox badge1.
- Direct source review: 960×660, EN/ES, conflict plus unsaved draft, manual decisions.
- Linked Macs: 540×680, EN/ES, preserved pending proposal and retry.
- Shared selection: 540×360, Spanish, folder plus document.
- Service preferences: 580×620, EN/ES, default-off service/private overlay and empty inboxes.

## iOS captures

Signed iPhone17ProMax Simulator, iOS26.5. `ios-git-integrated.png` and `ios-git-deleted-open-document.png` come from successful real SSH/UI acceptance on the final signed mobile/shared sources (121.599 seconds UI, 139.294 seconds server): generated-key scoped import, offline mutations/restart, immutable publication, desktop integration deleting an open document, consumption and second publication. The open deleted document reports its removal and disables Edit. The independent server verifies the second publication still omits that path, exact remaining bytes/ancestry and no excluded large-code blob request. [Git acceptance provenance](git-acceptance.json) records results and source hashes.

`ios-direct-revoked.png` comes from successful HTTPS/UI enrollment, read-only refresh, offline retention, retry and revocation acceptance on these final signed iOS sources (53.320 seconds UI, 53.364 seconds server). The capture shows Access withdrawn with Edit disabled, without an alert masking the state. An independent owned-container check confirms the project corpus and grant are absent. [Direct acceptance provenance](direct-acceptance.json) records results and source hashes. Final hosted CI and strict judgment must cover the delivered head.

### [#342](https://github.com/PinedaTec-EU/LeonardoMD/issues/342) Mac-requested rubric capture

`ios-rubric-capture-es.png` is the Spanish iPhone18Pro/iOS27.0 Simulator
sent-state capture; `ios-rubric-capture-es-drawing.png` and
`ios-rubric-capture-es-preview.png` preserve the real drawing and pre-send
preview states from the same run of
`PairingUITests/testMacRequestedRubricCaptureDrawsRestoresAndSendsOverPinnedHTTPS()`.
The real signed UI test uses only simulator
`A5A73B11-EE27-40AC-ABAB-CADF1B85143B` and a synthetic owned Mac fixture over
the pinned HTTPS transport. It accepts the targeted request, draws with the
native canvas, exercises undo/clear/preview, terminates and relaunches before
Send to restore the unsent draft, then sends the frozen response; the fixture
verifies the response received on the Mac. Exact capture, response, per-state
hashes and source metadata are in [ios-rubric-capture-es.json](ios-rubric-capture-es.json).

The same source checkpoint also passes the corrective native regressions:
`PairingUITests/testMacRequestedRubricCaptureLostAcknowledgementReconcilesAfterRelaunch()`
holds a real committed response behind a 503 gate through termination/relaunch,
then reconciles the same request ID after the gate opens; and
`PairingUITests/testGrantedReaderAndUnsentRubricBlocksAfterForegroundRevocation()`
keeps the accepted drawing visible but unsendable after foreground revocation,
purges the exact direct reader cache, and preserves the unrelated `QA · Markdown`
and legacy `QA · Recovery` corpora. The delayed-project regression holds a
real authorized response until foreground revocation and proves that the late
response cannot resurrect the cache or UI. Enrollment and capability snapshot
failure regressions remain fail-closed across relaunch, cache-deletion failure
is surfaced and retried to physical purge, and reconnect-during-purge preserves
a new grant for the same project. The final result paths, fixture roots and
JSON evidence hashes are recorded in the sidecar; these are simulator-only
checks, not physical-device or production-network claims.

This is capture-only: it does not grant document access or editing, and does
not claim physical-device networking, App Store/TestFlight distribution or a
production Mac. The existing reader navigation/offline corpus remains a
separate behavior.

### Recovery matrix before the terminal approval correction

The recovery-matrix capture/code checkpoint is `c8e52592e6325746237ef9d99f88ea41363d6262`. Its immutable drawing, preview and sent captures and all ten native mode results are recorded in [the source-bound manifest](ios-rubric-capture-final-20261106-c8e5259.json). Earlier raw captures/sidecars remain historical. The final independent iOS rebuild kept every app bundle file byte-identical to the installed capture product. All 34 relevant Swift/test/config inputs and package manifests match the captured source.

Current validation: 690 XCTest cases (655 passed, 35 optional skips, no failures) plus 70 Swift Testing cases across nine suites; nine focused iOS cases (two identity and seven revocation cases); ten native UI modes, each one pass/no failures/no skips. Both current guide packages pass three Python checks and five fresh native guide checks.

The two additional native modes preserve a lost acceptance acknowledgement through relaunch and keep inherited security uncertainty quarantined until authenticated STATUS. The acceptance recovery proof records one response POST for one explicit Send. Full-request identity matching rejects a colliding ID from another peer and conflicting concurrent payloads ([#367](https://github.com/PinedaTec-EU/LeonardoMD/issues/367)); identical concurrent sends coalesce ([#365](https://github.com/PinedaTec-EU/LeonardoMD/issues/365)).

These remain signed Simulator/owned synthetic HTTPS fixture and native guide-component checks. Owner TestFlight installation, physical iPhone networking, real compatible Mac startup/save/insertion/restart and production-network outcomes remain separate acceptance gates in [#343](https://github.com/PinedaTec-EU/LeonardoMD/issues/343).

### Terminal approval checkpoint before preview capture readiness

This earlier source checkpoint is `0d34b7b4c00960014f993ce471946b654b73840d`. [Its manifest](ios-rubric-capture-final-20261106-0d34b7b.json) binds five raw native captures (approval, drawing, preview, sent and blocked) and three current runs: terminal cancellation during Accept, normal roundtrip, and lost acceptance acknowledgement/relaunch. Each reports one pass, no failure and no skip. Nine current iOS unit tests pass. The final full host run reports 690 XCTest cases (655 passed, 35 optional skips) plus 70 Swift Testing cases across nine suites, without failures. The final independent iOS rebuild keeps every app bundle file byte-identical to the capture product.

The previous ten-mode recovery matrix remains bound to its c8 source; it was not rerun in full for this approval-view correction. Core draft, acceptance, submission, journal, client and persistence inputs are unchanged. Existing bilingual Guide v15 already describes terminal cancellation/expiry/revocation and asking the Mac for a new request; its package bytes and guide-test inputs remain unchanged. The correction removes invalid live approval actions and stale retry advice. Physical iPhone, TestFlight and production Mac acceptance remain open in #342/#343.

## Reproduction and limits

### #380 native HTTPS diagnostic fixture

`MobileDirectAcceptanceFixtureTests.testServeNativeMobileAcceptanceFixture`
starts a synthetic `DesktopDirectRuntime` on loopback port `46993`. Give each
run a fresh, owned root whose `.qa-fixture-owned` file contains exactly
`LittleLeonardoDirectQA\n`; the fixture rejects an existing `ready.json`.
Set `LEONARDO_MOBILE_DIRECT_QA_ROOT` for the recorded host `swift test` command
and wait for that root's `ready.json` before starting iOS UI automation.

The iOS XCTest runner does not inherit shell environment variables. After the
final `build-for-testing`, patch the generated `.xctestrun` dictionary
`LittleLeonardoUITests.EnvironmentVariables` with `LEONARDO_DIRECT_QA=1`,
`LEONARDO_DIRECT_QA_PORT=46993`, `LEONARDO_DIRECT_QA_HOST=127.0.0.1`, and
`LEONARDO_DIRECT_QA_PHASE_FILE=<fresh-root>/phase.txt`. Rebuilds replace that
patch. For bounded simulator runs use `-collect-test-diagnostics never`.
When reusing the owned A5 simulator after a previous direct-LAN fixture, first
preserve its test app data and reset only the `eu.pinedatec.LittleLeonardo`
bundle; a stale peer can make unrelated refresh/revocation assertions fail.

#### #380 transport diagnostic validation

The initial diagnostic checkpoint is source `0d9ec261dc6656a77fc852277addf40802c03255`
at compilation build delta 20. The focused `LeonardoSyncTransportTests` run
passes 17 tests, including
`HTTPSRuntimeTests.testInterruptedPinnedTLSBodyReportsBoundedPartialTransferContext()`;
that real TLS cutoff verifies a partial byte count without changing pinning or
transport bounds. The English/Spanish native guide and practice checks pass 7
tests, and the guide packaging checks pass 3 tests.

`PairingUITests/testNativeDirectEnrollmentRefreshOfflineRetentionRetryAndRevocation()`
passes 1/1 on the owned iPhone 18 Pro Simulator (iOS 27.0, build 24A434; delta
20). [The raw alert capture](ios-https-diagnostic-alert-20261106.png) shows the
existing alert with `[LL1 op=status domain=NSURLErrorDomain code=-1004 http=?
bytes=0/?]`. The loopback fixture intentionally stops for the status-failure
step and then verifies recovery. This proves the alert display and recovery
flow; it does not reproduce the owner's interrupted large snapshot. Full run,
fixture scope, timestamps and SHA-256 values are in
[the evidence manifest](https-diagnostic-evidence-20261106.json).

The [English](user-guide-https-diagnostic-en-20261106.png) and
[Spanish](user-guide-https-diagnostic-es-20261106.png) screenshots are the
original native WKWebView captures from that checkpoint. Their context sidecars bind
each locale to the same source and capture session. The follow-up run's PNG for
each locale has the same SHA-256 as its initial-run image; decoded pixel checks
also find the inline-code background in all four files. This invalidates the
apparent missing-line capture discrepancy recorded in [#388](https://github.com/PinedaTec-EU/LeonardoMD/issues/388);
no product rendering failure or capture-code change is claimed.

The owner's 338,658-byte image still fails on the physical iPhone after a
normal Mac editor restart. Its cause is unconfirmed; these diagnostics do not
resolve #380 and no TestFlight build is claimed.

#### #380 Guide v22 after merging PR #377

The combined source is `7ab7adadc2c46ebf96416f9658b1edf790ea654b`, based on
materialized PR #377 source `843670bcd3d5548242f04f11226e06487b3e790b`.
Guide v22 keeps the new interrupted-transfer example and includes the merged
math/outline help. Python packaging checks pass 3/3; the native guide and
practice suite passes 7/7 at build delta 21. A source-bound `--skip-build`
capture run passes those same seven tests, and the practice evidence run passes
1/1 after filling, saving, closing and reopening the form.

The [current English](user-guide-https-diagnostic-en-20261106-7ab7ada.png) and
[Spanish](user-guide-https-diagnostic-es-20261106-7ab7ada.png) frames show the
diagnostic example in the merged Guide v22. [Practice action and saved form
captures](https-diagnostic-evidence-20261106-7ab7ada.json) record both locales
with original context sidecars and source hashes. The preceding source-0d iOS
alert capture remains representative: `Sources/LeonardoSyncTransport`,
`Mobile/LittleLeonardo`, and their transport/UI test inputs are unchanged through
the merge. The preceding guide captures remain historical for the pre-merge
guide; use these new frames for the combined content. The physical large-image
failure remains unconfirmed.

Compile delta193 passes 340 XCTest cases (ten optional skips) and twelve renderer tests. Native Git acceptance also passes with the corrected fixture (138.046 seconds UI, 143.760 seconds server), independently verifying both publications, deletion, ancestry, excluded-blob omission and `git fsck`; the provenance manifest records this repetition separately from the retained captures. Delta193 adds only fail-fast guards to the separate publication regression; the native fixture and mobile/shared sources are unchanged. The real SSH fixture gives both upload-pack and receive-pack a 60-second post-EOF deadline, followed by a bounded cleanup check, within the unchanged 120-second transport timeout. A stalled session returns a specific remote-command diagnostic with session/PID, input/output bytes and separate termination/stream state; incomplete cleanup is reported explicitly. The controlled faults use a two-second deadline.

`testRealGitPublicationFaultPreservesPreparedJournalForExactRetry` fails one real SSH publication, verifies the remote ref and journal bytes are unchanged and the child/streams are closed, reloads the journal, then sends the identical commit/request exactly once. It verifies the resulting ref, file bytes and `git fsck` before persisting the published corpus and removing the journal. This exercises the shared durable-publication components; journal orchestration is composed explicitly by the test. The original intermittent stall is not conclusively attributed; [#121](https://github.com/PinedaTec-EU/LeonardoMD/issues/121) is addressed by a reproducible, specific failure guarantee rather than an unexplained rerun.

`LEONARDO_LOCALIZATION_EVIDENCE=<owned-output> swift test --skip-build --filter 'DesktopGitControllerTests|DesktopPeerNativeAcceptanceTests|LocalizationVisualTests.testCaptureIncomingSourceReviewInBothLanguages|LocalizationVisualTests.testCaptureDesktopPeerPreferencesInBothLanguages|LocalizationVisualTests.testCaptureScopedSharingInBothLanguages|LocalizationVisualTests.testCaptureDisabledMobileServiceInBothLanguages'` captures desktop evidence after compilation. Native iOS tests require signed build-for-testing and explicitly owned server fixtures documented in `doc/mobile/little-leonardo.md`.

These fixtures establish native controller/UI behavior; they do not claim a fresh packaged desktop process, physical QR camera, two physical Macs or live VPN. Git filtering depends on server support and fails closed without a full clone fallback. Unreachable revoked peers retain their cache until next contact.
