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
  original source digest for insertion safety. That reuse is bounded to the
  five-minute lost-acknowledgement window: a helper `notFound` after the window,
  an expired/pruned known request, or a legacy record without provenance is a
  local tombstone and can only be followed by **Request again** with a fresh ID.
- Cancellation is a separate durable intent from a remote `notFound` tombstone.
  If the user cancels while create is in flight, a late create is immediately
  reconciled with a remote cancel; until that succeeds the UUID remains
  queryable but cannot be reviewed, inserted or saved. A late completed reply
  can recover a technical missing tombstone, never an explicitly cancelled
  intent. If the companion completed just before cancellation was confirmed,
  the store records `completedBeforeCancellation`, discards the response, and
  exposes a terminal **Request another rubric** action without claiming that a
  remote cancel succeeded.
- Recovery prioritizes an unsaved returned response over a newer cancellation
  marker for the same document, even after the document source digest changes;
  saving the response remains available while insertion still checks the
  original context.
- `RubricLibrary` records the stable request UUID so repeated saves do not
  duplicate entries. Delayed status replies cannot regress cancellation or
  completion; the focused `RubricCaptureTests` covers restart/idempotence and
  this monotonic lifecycle rule.

## iOS response channel ([#342](https://github.com/PinedaTec-EU/LeonardoMD/issues/342))

The linked Little Leonardo companion remains read-only for documents. A mobile
device may additionally be approved with the optional `rubricExchangeV1`
capability and zero project grants. An authenticated capability refresh keeps
kind, grants, credential and cached documents unchanged; an older Mac that
does not expose that endpoint falls back safely to the existing reader path.
The server's `DirectDeviceStatus.capabilities` remains the server handler
status, not a client announcement, and optional V1 fields preserve legacy
decoding.

The active iOS request card persists a `pendingAcceptance` intent before remote
acceptance and enables ink only after the accepted local draft commits. The
accept transition is idempotent for the same authorized target; restart and
lost-acknowledgement recovery reuse the intent without replacing advanced ink
or a frozen response ([#362](https://github.com/PinedaTec-EU/LeonardoMD/issues/362)).
The card requires explicit Accept or Reject and then offers
label, finger/Pencil drawing, Undo, Clear, Preview and explicit Send. The canvas
matches the portable renderer's brush taper and single-point dots, samples a
conservative 600-point budget, and preflights the complete 24 KiB response
envelope. Before Send, the label and drawing are durable draft fields
independent of any response; closing/reopening the app restores them. Send
freezes one portable response before network I/O. `pendingSend` retries the
exact bytes after a transient error; `submitted` never regresses, while expiry,
cancellation or revocation blocks sending. The frozen card presents a locked
preview. The Mac receives only the response for the matching request, target
and linked TLS identity.

Draft snapshot writes register in UI-event order before asynchronous work starts
([#360](https://github.com/PinedaTec-EU/LeonardoMD/issues/360)). Blocked and
submitted drafts expire after 30 days; pending acceptance, accepted drawings
and pending-send work stay
recoverable. Capacity cleanup is committed only after a successful write
([#361](https://github.com/PinedaTec-EU/LeonardoMD/issues/361)).

Mobile connection snapshots and visibility policy live in
`MobileDirectConnectionStore.swift`; per-connection capture generations and
monotonic deny state live in `MobileDirectAuthorization.swift`.
`MobileRevocationJournal.swift` persists an independent uncertainty marker before
authenticated network work, coordinated through `MobileRevocationClient.swift`.
A failed preflight sends no request. Ordinary reloads preserve offline reading
for operations belonging to the current live journal session. An operation
inherited from another session quarantines only
its link until authenticated STATUS revalidation; an offline result or late
completion cannot undo inherited uncertainty or confirmed denial. This protects
restart even when post-response snapshot and credential writes both fail.
Confirmed revocation retires the Keychain credential and retains cache cleanup;
a missing item reconstructs revocation, while a Keychain read error stays
retryable. Serialized cache writes/removals check epochs and active owners,
including rollback and deferred cleanup
([#359](https://github.com/PinedaTec-EU/LeonardoMD/issues/359)). See the
[persistence contract](../doc/mobile/rubric-exchange.md#security-and-persistence).

Native evidence is recorded under
`doc/validation/little-leonardo/ios-rubric-capture-es.png` plus the drawing and
preview state captures, with per-state hashes in the JSON sidecar. It is a
signed iPhone18Pro/iOS27.0 Simulator run against the owned Mac HTTPS fixture,
not physical-device, App Store/TestFlight or production network evidence.
The final source-bound evidence and storage/reconnect regressions are tracked
in [PR #352](https://github.com/PinedaTec-EU/LeonardoMD/pull/352). Earlier
checkpoints remain in Git history and must not be treated as proof for later
corrective code; use the source and hashes in the current sidecar.

Cached draft presentation and reuse compare the complete immutable request
identity, ignoring only lifecycle state. In-flight submission reuse also compares
the normalized label and portable drawing; mismatches cannot share another
request's result ([#367](https://github.com/PinedaTec-EU/LeonardoMD/issues/367)).
Explicit sends/retries and foreground reconciliation share one identical
in-flight response operation ([#365](https://github.com/PinedaTec-EU/LeonardoMD/issues/365)).

The published bilingual guide is v15; #337's Synchronization role pages remain
in chapters 14–15 and previous personal guide copies are preserved.

The live approval card now observes a blocked acceptance immediately, removes
Accept/Reject and stale retry advice, and asks for a fresh Mac request. Native
cancellation during Accept and relaunch coverage is recorded with the current
[source-bound manifest](../doc/validation/little-leonardo/ios-rubric-capture-final-20261106-8488e9d.json)
([#356](https://github.com/PinedaTec-EU/LeonardoMD/issues/356)).

Native preview evidence waits for actual rendered ink before capture and checks
its density against the drawing, avoiding premature blank Canvas attachments
([#355](https://github.com/PinedaTec-EU/LeonardoMD/issues/355)). Capture-only Mac
consent is localized in EN/ES and has native component captures with zero project
grants and the comparison-code confirmation still required
([#370](https://github.com/PinedaTec-EU/LeonardoMD/issues/370)).

## Owner-only iOS distribution

The packaging stage of [#343](https://github.com/PinedaTec-EU/LeonardoMD/issues/343) uses `scripts/package-ios-distribution.py`: author `archive` rejects dirty tracked/untracked source except its own PR's ledger entry, binds source-input hashes to `HEAD`, and records the source PR compilation; `publisher-archive --expected-source <accepted-materialized-SHA>` requires a fully clean checkout whose `HEAD`, expected SHA and fetched `origin/main` match at startup, while preserving detached-HEAD support and the consumed allocation. Archive/export/Apple validation retain producer provenance and complete artifact hashes; later `origin/main` advances do not restamp an existing producer. Export selects the approved certificate without mutating the user keychain search list. Privacy reasons, opaque existing-brand icons, canonical version projection and exact delivery commands are documented in `doc/mobile/rubric-exchange.md`. A validated author IPA is not the final TestFlight delivery; upload accepted materialized main, then verify owner availability and the physical round trip before closing the feature issues.


## Read-only status recovery (#394)

[PR398](https://github.com/PinedaTec-EU/LeonardoMD/pull/398) serializes helper
configuration reads with a FIFO barrier; queued commands re-read persisted
consent instead of sharing a possibly obsolete configuration result. A cancelled
queued read releases its turn without reloading. RubricCapturePolling retries
only read-only status for the original UUID, up to three consecutive failures;
success resets that budget, cancellation stops, persistent errors remain visible.
It never creates or resubmits a request. The owner-observed response had already
reached the helper; a manual same-ID Retry recovered it before this correction.
Delivery and physical no-manual-Retry acceptance remain separate gates on
[issue394](https://github.com/PinedaTec-EU/LeonardoMD/issues/394).
