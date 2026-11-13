# Rubric exchange protocol

Issue [#340](https://github.com/PinedaTec-EU/LeonardoMD/issues/340) defines a
narrow request/response protocol between the Mac owner and a linked iOS reader.
It does not make mobile documents editable and it does not replicate a rubric
library to a group.

## Capability and scope

The protocol accepts an explicit `rubricExchangeV1` capability during pairing
and persists it in the paired-device record. This is a capability contract, not
an automatic feature flag: the mobile handler advertises it only when the
request/list/accept/reject/submit path is complete. A capture-only mobile
enrollment may therefore be approved with zero project grants while retaining
the existing `readOnly` role. Already-linked mobile devices can refresh this
optional capability through the authenticated endpoint without changing kind,
grants, credential or document cache. A 404 from an older Mac is a safe
reader-only fallback. Legacy records decode with no capabilities and old Mac
decoders ignore the optional update fields. The Mac server separately advertises
its own handler capability through `DirectDeviceStatus`; that server status is
not redefined as a client announcement. A request is accepted only for one
explicit authorized `readOnly` device; desktop peers, revoked devices and
implicit group broadcast are excluded.

## Lifecycle

The Mac creates a request with a stable requester identity, optional label hint,
and a five-minute expiry. The iOS reader lists its targeted requests and may
accept or reject one. The Mac may cancel it. An accepted reader stores an
independent durable draft containing the label and drawing before it submits
one bounded `RubricResponse`; drawing, undo and restart do not set
`submittedAt`. On the first explicit Send, the response bytes and submission
time are frozen and saved as `pendingSend` before network I/O. The Mac reads the
exact response and never receives a document write capability. Expired,
cancelled, rejected or revoked requests cannot be answered. Identical retries
return the saved response, while a different retry for the same request is a
conflict. `submitted` never regresses after a late failure; transient failures
retain the frozen pending payload, while terminal invalidation blocks it.
Terminal records are retained for 30 days and then pruned; the mobile draft
store is bounded to 64 records and 2 MiB, with responses limited to 24 KiB.

## Security and persistence

All routes use the existing pinned TLS transport and bearer credential. Every
operation rechecks the read-only grant and binds target, requester and request
identities. The authority gate spans the durable store await, so revoke/disable
cannot interleave with an accept or response commit. JSON storage is atomic and
transactional, normalizes trusted parent aliases, rejects a final-file symlink,
loads only after a metadata byte bound, and applies owner-only `0600` mode.
Authority and ordinary mobile connection/draft mutations publish their next
snapshot only after persistence succeeds. A failed capacity rollover likewise
keeps the previous draft snapshot in memory.

Authenticated mobile operations first persist an independent write-ahead marker.
If that write fails, no authenticated request is sent. After an interrupted
operation, the marker quarantines its connection on reload/relaunch until a
fresh authenticated STATUS revalidates the link. An ordinary reload does not
quarantine operations owned by its current live journal session; confirmed
in-memory denial applies regardless of session. A transient/offline result
cannot resolve inherited uncertainty. A frozen drawing body is not sent before
that revalidation.

A confirmed mobile revocation is an immediate, monotonic deny barrier. It
invalidates only that connection's capture generation, records pending cache
removals and retires the credential from Keychain. The in-memory deny survives
ordinary library reload. If the connection snapshot and credential retirement
both fail, the independent write-ahead marker still survives restart; even a
failed post-response journal write leaves the earlier uncertainty marker in
place. Late operation completions must not clear a confirmed deny. File-write
and cache-deletion failures are surfaced rather than treated as completed
cleanup. A missing Keychain credential also reconstructs interrupted revocation;
a Keychain read error remains retryable, rather than meaning a missing item.

Pending cleanup retries on library reload. Known revoked direct caches stay
hidden while cleanup is pending; unrelated offline corpora remain readable.
Cache mutations are ordered and recheck connection generation and current
project ownership, so an old purge cannot delete a newly authorized cache.
An ordinary library reload does not revoke capture authorization, and revoking
one connection does not invalidate another connection's in-flight response.

## Runtime limits and validation

The protocol is pull-based: an inactive iOS process is not treated as a
continuously running background listener. Unsupported, offline and revoked
states remain explicit to callers. PR #344 records the protocol foundation;
the #342 implementation adds focused draft/state/legacy tests, a signed native
iOS UI test and an owned Mac HTTPS fixture. The native test covers a real
simulator accept/draw/undo/clear/preview/restart/send path and verifies the
response received by the Mac fixture. This is not physical-device,
App Store/TestFlight or production-network acceptance; distribution remains
[#343](https://github.com/PinedaTec-EU/LeonardoMD/issues/343).

## Mac owner capture flow (#341)

The macOS editor keeps this exchange behind the existing helper-owned runtime;
it does not start a second in-process listener or create a second rubric store.
When the helper and service are available, the New rubric dialog lists exactly
one enrolled read-only device at a time and names the requesting Mac with its
bounded local computer name. The owner creates a caller-generated request ID,
persists a local intent, sends the request through XPC, polls the durable status,
and can cancel it. A lost XPC reply is recovered with the same ID rather than
creating a duplicate request, but only inside the bounded five-minute
acknowledgement window. The local record stores creation-attempt provenance and
the deadline separately from its display/update timestamp. A helper `notFound`
after that window, or after a known request has expired or been pruned, creates a
local tombstone; **Request again** must use a fresh UUID and never recreate the
old request. Offline errors remain retryable within the window, while legacy
records without provenance are treated conservatively as requiring a new ID.

The returned drawing is previewed and must be explicitly saved to the existing
Mac library or saved-and-inserted. Library writes carry the request ID and are
idempotent across retries and restarts. Insertion rechecks the original
document URL and source bytes; if either changed, insertion is refused while a
library-only save remains available. Local capture records contain a SHA-256
source digest, not the document text, are atomically written with the existing
process lock, and keep unsaved completed responses until the user saves them.
Saved/terminal records are bounded and pruned only when safe. The owner UI
shows helper-offline, service-offline and unsupported-peer states. The current
Mac flow receives only the mobile rubric response and keeps the existing
explicit review/save boundary.

If the owner cancels while the helper create call is still in flight, the local
record stores a separate cancellation intent. A `notFound` cancel reply is not
treated as proof that no request will appear: a late create is followed by a
compensating remote cancel, and the old UUID is never reopened for review or
saved. If that compensation is temporarily unavailable, the intent and UUID
remain durable for reconciliation; **Request another rubric** is the only way
to start a fresh request. If the helper reports that the companion completed
just before cancellation could be confirmed, the Mac records a local
`completedBeforeCancellation` outcome, discards the returned drawing, and
shows a terminal message with **Request another rubric**; it does not pretend
that a remote cancellation succeeded or allow a library save.

## iOS draft and response boundary (#342)

`MobileRubricDraft` binds the request ID, linked connection identity, target
device, requester and pinned source fingerprint. Its persisted `drawing` and
`label` are independent of the optional response, so a user can close/reopen
the capture card before Send and recover unsent work. The state ordering is
`accepted → pendingSend → submitted`; `blocked` and `submitted` absorb late
errors without reopening or mutating a response. Response persistence compares
the frozen encoded content, not only a generated ID.

The mobile screen exposes explicit Accept/Reject, label, finger/Pencil drawing,
Undo, Clear, Preview and Send/Retry controls. It never sends a drawing merely
because it was drawn. The portable payload is a `LeonardoRubric` with a 24 KiB
encoded response limit. A successful Mac receipt is bound to the same
requester, target, request ID and TLS identity; expiry, cancellation and
revocation remain hard send barriers.

## Request identity invariant (#367)

The mobile cache and capture projection bind a request by its complete immutable
identity: request UUID, target device UUID, requester UUID, normalized requester
name, normalized label hint, capability, creation time and expiry time. Lifecycle
state is the only field that may change during recovery; a UUID alone can never
select another peer's cached draft or response. An in-flight submission may be
shared only when that full request binding, the normalized label, and the same
portable `LeonardoRubric` drawing all match. Any mismatch is rejected before
HTTP, including same-UUID requests from another Mac or a changed drawing. The
identity tests cover both cross-peer cache projection/accept/send rejection and
concurrent exact-operation reuse
([#367](https://github.com/PinedaTec-EU/LeonardoMD/issues/367)).

The validation matrix is deliberately asymmetric: a same-UUID request with a
different Mac requester, target device, capability, label hint or timestamp
must produce no cached projection and a pre-HTTP conflict for Accept and Send;
the same complete request with the same normalized label and identical ink may
share one in-flight operation; changing either the normalized label or ink must
remain a conflict even while that operation is running. This prevents a peer's
heading or drawing from being selected by ID alone and preserves the one-POST
coalescing contract for exact retries.

## Owner-only iOS distribution (#343)

`scripts/package-ios-distribution.py` is scoped to Little Leonardo
(`eu.pinedatec.LittleLeonardo`, team `AU2Z3P42U7`). Its CLI help lists the
required profile, signing identity/keychain and external output paths. It never
uploads or changes App Store Connect. Use a fresh output directory per producer.

1. Before integration, `archive --pr-number <source-PR>` builds Release through
   the repository compilation recorder. Commit source first and retain the log
   and generated `distribution-provenance.json`. Failed commands are not counted.
   Before profile validation, signing or compilation, the author guard requires
   all tracked and untracked changes to be clean except for that PR's own
   `deploy/version/entries/<source-PR>.yaml`, which may change as recorder
   bookkeeping. It records the committed source SHA and rechecks source inputs
   after the build. This exception does not apply to `publisher-archive`, which
   still requires the entire accepted-checkpoint checkout to be clean.
2. After accepted source integration and central version materialization, fetch
   `origin` and select the exact current accepted materialized `origin/main` SHA
   in a clean checkout. `publisher-archive --expected-source <full-SHA>` requires
   `HEAD`, the argument and fetched `origin/main` to match before it verifies the
   canonical checkpoint, consumed entries and clean inputs. Detached HEAD is
   supported. Producer provenance stays frozen at that source after startup; a
   later `origin/main` advance never restamps an existing archive or export.
3. Only after archive verification succeeds, `export` verifies the archive against
   its frozen producer and exports an owner-only App Store Connect IPA. It passes
   the approved certificate fingerprint and process-local signing scope without
   replacing the user's keychain search list.
4. Only after export succeeds, `validate` verifies the recorded IPA digest and
   runs Apple's package validation with the existing authorized API key. This
   checks the package without uploading it. Upload and owner internal-group
   assignment remain a separate authorized publication step after integration.

Marketing version is the complete canonical `version.nfo`; iOS bundle build is
its cumulative final numeric component, not an independent counter. Apple must
not rewrite either value. The export is internal-TestFlight-only. Verification
requires the approved team/profile/certificate, opaque existing-brand icons,
launch/orientation metadata, packaged resources and privacy reasons `CA92.1`
(own UserDefaults) and `C617.1` (own-container file metadata); no external-file
read reason is declared. Release archives must exclude tests and XCTest.
Provenance freezes source/input hashes and complete archive/app/IPA hashes
through archive, export and Apple validation. Evidence-only commits must explain
their source equivalence; never restamp an older artifact as a newer producer.

A validated author artifact is not the final delivered build. Publish accepted
materialized main, await Apple processing, attach that specific build to the
owner internal group and verify installation from TestFlight. Keep
[#343](https://github.com/PinedaTec-EU/LeonardoMD/issues/343) open until the real
device permissions, pairing, offline reading, request/draw/send, Mac review,
save/insert/restart and terminal/retry/revocation checks are recorded. Simulator
Home rendering limitations do not establish physical icon appearance.

### iOS export compliance

Little Leonardo declares `ITSAppUsesNonExemptEncryption = false` in its generated Info.plist, consistent with the classification used for TestFlight build 1279. The distribution verifier requires a Boolean false in the packaged app. Reassess this declaration before release whenever cryptographic functionality or linked dependencies change, including third-party libraries; Apple may require a different declaration or documentation. See [Apple’s guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).
