# HTTPS response lifetime investigation

Canonical bug: [#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380).

The owner supplied `physical-partial-body-20261107.png`, captured on a physical iPhone at11:47 on7 November2026. It shows `[LL1 op=snapshot domain=NSURLErrorDomain code=-1005 http=200 bytes=409481/492904]`. Original PNG1290×2796, SHA256 `aca7654d20637b3a6d96d3898c155906932543951a6b5585eb548d5064783de6`. The image does not expose the installed build; correlate it with the diagnostic thread rather than guessing from TestFlight availability.

The response header arrived;83,423 declared bytes were not consumed. Root cause is not established by the screenshot. The server currently sends under the default message context and cancels after stack processing. Investigate explicit final-message write-close and remote EOF before teardown under delayed consumption. Existing passing loopback/constrained-window tests do not prove physical-device success.

Preserve the owner's helper, pairing, trust pin and granted corpus. Tests use isolated loopback listeners and temporary identities. No delivered fix, native acceptance, helper replacement or new publication is claimed by this checkpoint.


## Candidate and evidence limits

The independent Python TLS peer pins the exact throwaway certificate and uses
strict EOF handling (`suppress_ragged_eofs=False`). The original server already
passes a492,904-byte body and a2MiB response with a1KiB TCP receive window
negotiated before connect and delayed reads. Therefore missing `close_notify`
is not established as the physical cause. An initial OpenSSL state-text check
was discarded because absent state text was not a reliable EOF observation.

An unchanged iOS27.0 Simulator client (producer0055, same reader code as1082)
also received the original338,658-byte PNG through an isolated enrolled fixture;
the SHA256 was168ec2a62e8faf0ddeb3e895a25bd024b9fc8ec826a53dc9c91b19b38addc090.
The server fixture passed1/1. The route to the host LAN address used `lo0`, so
this is supplementary simulator evidence, not a reproduction of physical Wi-Fi.
The diagnostic thread restored the owned QA app's15 original files; the real
helper, pin and grants were never changed.

The candidate makes response termination explicit using Network's documented
[final-message write-close](https://developer.apple.com/documentation/network/nwconnection/send(content:contentcontext:iscomplete:completion:)-5ecuz).
It waits for peer close with a five-second cap before cancelling the connection.
This removes immediate teardown as a dependency of response completion, but it
is a bounded protocol change under investigation, not proof of the original
physical root cause or a delivered fix. A16-peer test deliberately withholds
client EOF and confirms that another request is admitted after the grace period.

The server now emits a bounded completion fact record including attempted
body/encoded lengths, phase, finish reason and network error number. All counts
are local stack facts, never remote delivery receipts. Tests verify that an
arbitrary error domain/description/path sentinel cannot enter this record.
Source/receiving APIs, TLS pinning, grants, HTTP framing and read-only cache
contracts stay unchanged. No retry hides a truncated response.

## Acceptance still required

The diagnostic thread is collecting allowlisted live network events from the
unchanged source helper for one owner-controlled physical retry. Candidate
installation, physical successful transfer/rendering, final exact-head CI and
independent judgment remain pending. Do not close #380 or publish a resolution
based only on the passing local probes. No packaged GUI instance was launched
by this investigation; the native UI lease remains with #387.

## Current candidate checks

Full local suite:711 XCTest checks,35 opt-in/platform skips,zero failures;28 Swift Testing checks pass. Generic iOS Simulator compilation succeeds. The server's stop, bounds, pin mismatch, interrupted body, pairing and revocation regressions remain covered; new tests cover independent strict TLS EOF/delayed reads,16 held-open peers, second-request rejection during teardown, and diagnostic privacy. Successful compiler invocations are recorded in PR392's own entry, not the consumed382 entry.

This candidate changes no visual controls, renderer, user prerequisites or guide content. Existing bilingual LL1/offline/retry guidance remains accurate; the internal LLS1 support record is documented here and in the technical mobile contract. No new packaged app instance was used by these checks, so no fresh packaged Help acceptance is asserted.

## Signed local candidate checkpoint

The real executable/helper were built from source `cc6c43f7845c61a3fe24f8e862e8ab7f82fc50c5`, then signed inside-out with the existing Developer ID Application (teamAU2Z3P42U7). Canonical package verification confirms dependency resolution, nested signatures and no XCTest linkage. `candidate-package.json` binds the original application/helper/archive bytes to this source. The local display version remains baseline0.3.1082; it is not a newly materialized or published release. Compilation allocation is11.

An immutable canonical bundle and a separate signed disposable QA copy are ready. Neither was launched or installed. Native control reported the Mac locked with automatic unlock paused after physical input before inspection could begin. The unlock request is centralized in the385 thread. Original preferences and the exact EN/ES practice files were backed up; none was modified during this attempted native phase. The diagnostic thread retains ownership of helper replacement/rollback and the next physical test. The installed helper, pins, grants and corpus remain intact.

The owner reported the same LL1 byte counts again. That line came from an additional retry after the allowlisted live collector stopped, so it is not bound to a particular connection in the preceding controlled capture. Do not infer queued/body lengths from TCP summary counters or treat the repeating pattern as conclusive causality.
