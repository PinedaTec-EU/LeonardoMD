# Little Leonardo native validation

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

## Reproduction and limits

Compile delta193 passes 340 XCTest cases (ten optional skips) and twelve renderer tests. Native Git acceptance also passes with the corrected fixture (138.046 seconds UI, 143.760 seconds server), independently verifying both publications, deletion, ancestry, excluded-blob omission and `git fsck`; the provenance manifest records this repetition separately from the retained captures. Delta193 adds only fail-fast guards to the separate publication regression; the native fixture and mobile/shared sources are unchanged. The real SSH fixture gives both upload-pack and receive-pack a 60-second post-EOF deadline, followed by a bounded cleanup check, within the unchanged 120-second transport timeout. A stalled session returns a specific remote-command diagnostic with session/PID, input/output bytes and separate termination/stream state; incomplete cleanup is reported explicitly. The controlled faults use a two-second deadline.

`testRealGitPublicationFaultPreservesPreparedJournalForExactRetry` fails one real SSH publication, verifies the remote ref and journal bytes are unchanged and the child/streams are closed, reloads the journal, then sends the identical commit/request exactly once. It verifies the resulting ref, file bytes and `git fsck` before persisting the published corpus and removing the journal. This exercises the shared durable-publication components; journal orchestration is composed explicitly by the test. The original intermittent stall is not conclusively attributed; [#121](https://github.com/PinedaTec-EU/LeonardoMD/issues/121) is addressed by a reproducible, specific failure guarantee rather than an unexplained rerun.

`LEONARDO_LOCALIZATION_EVIDENCE=<owned-output> swift test --skip-build --filter 'DesktopGitControllerTests|DesktopPeerNativeAcceptanceTests|LocalizationVisualTests.testCaptureIncomingSourceReviewInBothLanguages|LocalizationVisualTests.testCaptureDesktopPeerPreferencesInBothLanguages|LocalizationVisualTests.testCaptureScopedSharingInBothLanguages|LocalizationVisualTests.testCaptureDisabledMobileServiceInBothLanguages'` captures desktop evidence after compilation. Native iOS tests require signed build-for-testing and explicitly owned server fixtures documented in `doc/mobile/little-leonardo.md`.

These fixtures establish native controller/UI behavior; they do not claim a fresh packaged desktop process, physical QR camera, two physical Macs or live VPN. Git filtering depends on server support and fails closed without a full clone fallback. Unreachable revoked peers retain their cache until next contact.
