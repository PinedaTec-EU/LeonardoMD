# Rubric exchange protocol

Issue [#340](https://github.com/PinedaTec-EU/LeonardoMD/issues/340) defines a
narrow request/response protocol between the Mac owner and a linked iOS reader.
It does not make mobile documents editable and it does not replicate a rubric
library to a group.

## Capability and scope

`rubricExchangeV1` is advertised by the mobile client during pairing and is
persisted in the paired-device record. A legacy record decodes with no
capabilities, so the Mac reports `unsupported` instead of creating a request
that the peer cannot answer. The Mac server separately advertises its own
capability through `DirectDeviceStatus`. A request is accepted only for one
explicit authorized `readOnly` device; desktop peers, revoked devices and
implicit group broadcast are excluded.

## Lifecycle

The Mac creates a request with a stable requester identity, optional label hint,
and a five-minute expiry. The iOS reader lists its targeted requests and may
accept or reject one. The Mac may cancel it. An accepted reader submits one
bounded `RubricResponse`; the Mac reads the exact response and never receives a
document write capability. Expired, cancelled, rejected or revoked requests
cannot be answered. Identical retries return the saved response, while a
different retry for the same request is a conflict. Terminal records are
retained for 30 days and then pruned; the store is bounded to 256 records and
16 MiB, with responses limited to 24 KiB.

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
states remain explicit to callers. PR #344 validates the lifecycle with eight
focused exchange tests and an actual pinned HTTPS request/accept/response,
duplicate-retry and revocation round trip. Full-suite CI and an independent
judgment remain required. User-facing iOS/Mac screens are follow-up work in
[#341](https://github.com/PinedaTec-EU/LeonardoMD/issues/341) and
[#342](https://github.com/PinedaTec-EU/LeonardoMD/issues/342); TestFlight is
[#343](https://github.com/PinedaTec-EU/LeonardoMD/issues/343).
