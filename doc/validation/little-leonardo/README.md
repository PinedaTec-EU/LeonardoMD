# Little Leonardo native validation

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

### Final terminal approval validation

Current source is `0d34b7b4c00960014f993ce471946b654b73840d`. [Its manifest](ios-rubric-capture-final-20261106-0d34b7b.json) binds five raw native captures (approval, drawing, preview, sent and blocked) and three current runs: terminal cancellation during Accept, normal roundtrip, and lost acceptance acknowledgement/relaunch. Each reports one pass, no failure and no skip. Nine current iOS unit tests pass. The final full host run reports 690 XCTest cases (655 passed, 35 optional skips) plus 70 Swift Testing cases across nine suites, without failures. The final independent iOS rebuild keeps every app bundle file byte-identical to the capture product.

The previous ten-mode recovery matrix remains bound to its c8 source; it was not rerun in full for this approval-view correction. Core draft, acceptance, submission, journal, client and persistence inputs are unchanged. Existing bilingual Guide v15 already describes terminal cancellation/expiry/revocation and asking the Mac for a new request; its package bytes and guide-test inputs remain unchanged. The correction removes invalid live approval actions and stale retry advice. Physical iPhone, TestFlight and production Mac acceptance remain open in #342/#343.

## Reproduction and limits

Compile delta193 passes 340 XCTest cases (ten optional skips) and twelve renderer tests. Native Git acceptance also passes with the corrected fixture (138.046 seconds UI, 143.760 seconds server), independently verifying both publications, deletion, ancestry, excluded-blob omission and `git fsck`; the provenance manifest records this repetition separately from the retained captures. Delta193 adds only fail-fast guards to the separate publication regression; the native fixture and mobile/shared sources are unchanged. The real SSH fixture gives both upload-pack and receive-pack a 60-second post-EOF deadline, followed by a bounded cleanup check, within the unchanged 120-second transport timeout. A stalled session returns a specific remote-command diagnostic with session/PID, input/output bytes and separate termination/stream state; incomplete cleanup is reported explicitly. The controlled faults use a two-second deadline.

`testRealGitPublicationFaultPreservesPreparedJournalForExactRetry` fails one real SSH publication, verifies the remote ref and journal bytes are unchanged and the child/streams are closed, reloads the journal, then sends the identical commit/request exactly once. It verifies the resulting ref, file bytes and `git fsck` before persisting the published corpus and removing the journal. This exercises the shared durable-publication components; journal orchestration is composed explicitly by the test. The original intermittent stall is not conclusively attributed; [#121](https://github.com/PinedaTec-EU/LeonardoMD/issues/121) is addressed by a reproducible, specific failure guarantee rather than an unexplained rerun.

`LEONARDO_LOCALIZATION_EVIDENCE=<owned-output> swift test --skip-build --filter 'DesktopGitControllerTests|DesktopPeerNativeAcceptanceTests|LocalizationVisualTests.testCaptureIncomingSourceReviewInBothLanguages|LocalizationVisualTests.testCaptureDesktopPeerPreferencesInBothLanguages|LocalizationVisualTests.testCaptureScopedSharingInBothLanguages|LocalizationVisualTests.testCaptureDisabledMobileServiceInBothLanguages'` captures desktop evidence after compilation. Native iOS tests require signed build-for-testing and explicitly owned server fixtures documented in `doc/mobile/little-leonardo.md`.

These fixtures establish native controller/UI behavior; they do not claim a fresh packaged desktop process, physical QR camera, two physical Macs or live VPN. Git filtering depends on server support and fails closed without a full clone fallback. Unreachable revoked peers retain their cache until next contact.
