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
Persistence failures leave in-memory state unchanged.

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
