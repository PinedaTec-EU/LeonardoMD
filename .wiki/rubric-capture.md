# macOS rubric capture

Issue [#341](https://github.com/PinedaTec-EU/LeonardoMD/issues/341) adds the
owner-side Mac flow on top of the authenticated exchange in
[`doc/mobile/rubric-exchange.md`](../doc/mobile/rubric-exchange.md).

- `DesktopSyncController` talks through the helper-owned XPC runtime, filters
  paired devices to non-revoked `readOnly` peers that persist
  `rubricExchangeV1`, and reports helper/service/peer availability separately.
- `RubricCaptureStore` keeps a bounded, atomic intent/status record keyed by the
  caller-generated request UUID. It stores a SHA-256 source digest rather than
  document text, uses `ProcessFileLock`, and keeps completed responses until an
  explicit library save is recorded. Persistence, retention and lifecycle
  ordering use the controller-injected clock, so a delayed reply cannot win
  merely because wall time moved backwards. Every terminal outcome is
  absorbing, including cancellation versus a late completion; the independent
  library-save marker is merged durably even when that clock rolls back.
- `RubricEditor` offers one target, polls/retries durable status, shows a native
  preview, and requires **Save to library** or **Save and insert**. The latter
  rechecks the original document URL/source through `SessionGraphics`; a
  changed document can still use the library-only path. After saving, **Request
  another rubric** starts a fresh stable-ID exchange; saved results no longer
  auto-occupy a reopened editor, while unsaved results remain recoverable.
  **Refresh linked devices** re-reads helper/consent state when a companion is
  upgraded while the editor is open. The initial intent is persisted before
  the asynchronous create call; a lost create/status acknowledgement leaves a
  visible Retry action that reuses the same UUID, and a retry preserves the
  original source digest for insertion safety.
- `RubricLibrary` records the stable request UUID so repeated saves do not
  duplicate entries. Delayed status replies cannot regress cancellation or
  completion; the focused `RubricCaptureTests` covers restart/idempotence and
  this monotonic lifecycle rule.

Production mobile enrollment remains capability-empty until #342 supplies the
request/draw/send UI. Protocol fixtures may advertise the capability, but the
Mac must not present an unsupported historical reader as a capture target.
The published bilingual guide is v14 because main also carries the #337
Synchronization role pages; Guide-v13 remains historical and is not bundled.
