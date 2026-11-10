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


## Corrective candidate validation

The candidate is based on main 0.3.1233 (`f04564a2`, including #408). Full
integrated checks passed: 766 XCTest checks, 39 skips, zero failures, plus
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
remain unchanged; the older Help executable is not relabeled. Current controller
UI captures are in `candidate-components-ready/`; earlier component captures are
retained as historical checkpoints. The automatic signed-service replacement is covered
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
