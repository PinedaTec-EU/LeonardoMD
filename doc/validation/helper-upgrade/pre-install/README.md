# Pre-install service preparation (#412)

The signed1215→1270 failure remains canonical at
https://github.com/PinedaTec-EU/LeonardoMD/issues/412#issuecomment-6775868256.
The owner requested a correction, then explicitly declined logout/recovery and
instructed preparation with signed installation validation pending.

This change gates the actual Sparkle Install reply, installation retry and the
install-on-quit path on cooperative service shutdown before bundle replacement.
Download approval and ordinary quit do not pause the background service.
A durable existing-consent token is resumed by the next process. The original
process cannot restart it through polling. Cancelled termination restores it;
explicit disable remains final. No forced kill, trust relaxation, pairing reset
or permission change is introduced. A live unreachable legacy helper still
vetoes installation because no drain acknowledgement or lifetime-lock ownership
can be established. External installers do not execute this preparation.

## Acceptance still pending

- A fresh packaged instance opening both Help51 locales and representative
  Mermaid/math/charts/images/tables plus practice save/reopen.
- Controlled recovery of the existing1215 process, authorized separately by owner.
- Two legitimately versioned, reviewed, signed installations A→B through the
  real update channel, with service A already running and preparation present
  in A. Verify new live helper identity/readiness without OFF/ON, immutable source
  and archive identities, and equality of all device grants and TLS identity.
- Owner's existing iPhone opening an authorized shared project and file without
  pairing again. Notify the owner only when the source is actually ready.

Automated checks supplement these rows. They must not be represented as an
installed PASS or used to close the issue.

## Automated result

Final local checks: 790 XCTest checks (41 opt-in skips), 72 Swift Testing checks,
118 Python checks (7 platform/opt-in skips) and 3 deterministic guide packaging
checks pass. `automated.json` binds the reviewed production source contents to
those results. Four successful compiler-bearing author invocations are recorded
in source PR420; publisher/CI runs do not mutate that allocation.
