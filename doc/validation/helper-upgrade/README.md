# Helper update failure and recovery

The original owner-provided iPhone screenshot is historical bug evidence for1215,
not a generated image or acceptance capture of this corrective candidate. Its
provenance is recorded separately: original bytes retained, native pixel viewport,
reported version and actual filename capture time. OS version was not provided.
No canonical synthetic QA metadata is invented for this owner screenshot.

`observed-1215-recovery.json` records the real normal master OFF/ON recovery:
old1136 stopped, installed1215 helper started, TLS identity and three access rows
preserved. Device-store bytes changed during runtime; exact store identity is
not claimed. Owner confirmed the already paired project and file now open.
This proves the operational cause and recovery, not the automatic412 fix.


## Current integration with main after #400

The current product source is `2ac7b7c5fb0566fea95b1652d3cd4766f3694cf8`,
which incorporates main `54c00e421adcaaadaba3de56a8e3d6465ad73ad3`. Guide45
combines the service-renewal instructions with the project-identity help from
#400 and preserves all earlier personal guide copies.

`candidate-help45/acceptance.json` records fresh packaged process PID16185,
its actual baseline 0.3.1233/build1233, both real Help-menu openings, verified
bundle/personal hashes, and all mandatory live examples. Sixteen full-size
original CUA captures include both practice save/close/reopen checks, Math OFF
fallback, and the two integrated feature sections. Original practice files were
restored byte-for-byte; English and Math ON were restored before normal quit.
The installed helper PID48295 remained running. This does not claim signed
installed automatic renewal. Input trees and automation results accompany it.

Full integrated validation passed: 779 XCTest checks, 41 skips, zero failures,
and 72 Swift Testing checks; generic iOS Simulator build and three deterministic
package checks also passed. No additional helper lifecycle code changed during
this integration. Earlier component captures remain scoped to their original
unchanged preference/controller inputs.

## Historical corrective candidate validation

The candidate is based on main 0.3.1233 (`f04564a2`, including #408). Full
integrated checks passed: 770 XCTest checks, 39 skips, zero failures, plus
72 Swift Testing checks. Generic iOS Simulator compilation passed. Three
package determinism tests passed. See `integrated-automated.json`.

`candidate-help40/` records a fresh real packaged process, PID65363, baseline
0.3.1233/build1233, with both guides opened through Help. Personal and bundled
hashes matched before acceptance. The mandatory live examples, Math on/off,
and separate fictional practice forms saved/closed/reopened passed in both
languages. Original practice files were restored byte-for-byte; English and
Math ON were restored, and the process quit normally. Installed helper48295
remained running. No production registration was changed by this candidate.

`candidate-components/` shows the production preferences section using a
synthetic helper held at graceful shutdown, then explicit disable. The actual
controller test also asserts persisted denial and no renewed registration.
This is native component evidence, not installed launchd upgrade acceptance.

Packaged Help and original component captures use source533ba927d191cf6248703b32bab84f87f15d1d45.
`candidate-inputs.git-ls-tree.txt` binds Sources, Tests, Mobile, package inputs,
scripts, assets and version.nfo. The clock-only checkpoint is mapped in `clock-input-mapping.json`. The subsequent
activation/readiness correction is mapped in `readiness-input-mapping.json`, with
a current full input tree. Help opening, content, renderer and practice inputs
remain unchanged; the older Help executable is not relabeled. Current lifecycle confirmation and input scope are recorded in
`autonomous-input-mapping.json` and `autonomous-inputs.git-ls-tree.txt`. Current
controller UI captures are in `candidate-components-autonomous/`; earlier
component captures remain historical checkpoints. The automatic signed-service replacement is covered
by controller tests with real temporary preferences and registration/XPC doubles;
a live automatic replacement in an installed Developer ID package remains a
post-publication check. The observed owner recovery above was manual.

Activation of an already-enabled legacy registration now calls identity-aware
refresh before it can report readiness. Peer adapters require an explicit gate
from their actual shared helper controller; the static legacy gate is removed.
Fresh health identity and a second persisted-consent read deny a first network
request when renewal/disable begins while health is in flight. Four pre-fix
regressions failed with12assertions; all pass afterward, as do current/newer
identity positive cases.

## Unattended startup readiness

A single normal startup refresh now waits for a bounded compatible health
confirmation after registration. No Preferences view supplies this lifecycle
step. The default policy allows five probes, with250ms async pauses between
probes; tests control pauses and do not depend on real delays. The probe phase
does not repeat registration. Exhaustion reports unavailable, and a subsequent
normal peer operation can recognize a helper that completed launch later.

The fresh-controller test makes exactly one startup refresh, handles a transient
health failure and delayed compatible identity, then performs a gated peer probe
without mounting Preferences or manually refreshing again. Separate tests cover
a bounded exhausted budget, explicit disable during a held startup reply, and
newer verified endpoint metadata surviving an older readiness response. These
are controller/temporary-store tests, not a newly launched packaged process.
The three startup regressions failed with six assertions before correction; the
delayed-metadata regression failed with one assertion. All now pass.

## Native measurement provenance

Native captures have no browser CSS viewport. `viewport_css` is null. CUA does
not expose native window/viewport points here, so those measurements are null;
only fixture-created AppKit components report their explicitly measured NSSize.
Image pixels remain separately recorded from the original file header. Earlier
bitmap/native-point equivalents in the browser field are corrected explicitly
in `native-provenance-correction.json`; original images, capture times and source
identities are preserved. Canonical helper image/source primitives support these
native records; its browser-only context validator requires CSS measurements and
is not used to invent them.

## Central version materialization

The integration also includes main `c009929d` (0.3.1246), satisfying the central
policy latest-base requirement. This changes only version/release metadata and
consumes #400’s ledger entry. Runtime, help, renderer and test input trees remain
identical to `2ac7b7c5`; `candidate-help45/materialized-main-mapping.json` records
the comparison. Captures keep their actual baseline1233 identity. Fresh CI on
the integrated head is required before the next judge.
