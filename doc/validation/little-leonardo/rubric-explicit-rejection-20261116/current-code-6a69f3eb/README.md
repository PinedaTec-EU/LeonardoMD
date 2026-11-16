# Explicit rubric rejection evidence

This folder records evidence for PR #435 against product source
`6a69f3eb1256c25517a2cccf8412eda9f4f3b740`.

The English native UI test passed on an iPhone 17 Pro simulator running iOS
26.5. It captured the HTTP 503 rejection, HTTP 413 invalid-payload rejection,
and terminal HTTP 409 after a deliberate manual retry. The test name includes
`English`; its launch arguments selected English even though the simulator's
registered device name contains “Spanish QA”. The test result bundle reports
one test passed, zero failed and zero skipped.

This is a historical capture of the error/retry behavior, not evidence that the
whole screen was localized. Its title, form labels, controls and instructions
are Spanish while the failure copy is English. The inconsistency is tracked in
[#462](https://github.com/PinedaTec-EU/LeonardoMD/issues/462); this folder is
superseded by the later clean-run evidence under `current-code-5e751df2/`.

The host fixture returned `[503, 503, 413, 409]` under one stable request ID.
It proves there was no automatic response POST after the first 503 or after
the 413; the later terminal 409 followed the user's explicit Retry. The 413
draft remains in `pendingSend`, has `requiresUserRetry: true`, and preserves the
response. The restored-draft fixtures cover recovery of the durable marker.

The implementation also has a session guard for the case where writing the
durable rejection marker itself fails. Its state transitions are unit-tested,
and reconciliation consults that guard. A forced storage-write failure was
not injected end-to-end: if storage remains unavailable across an app restart,
only the durable marker can protect the draft across that restart. This is a
documented residual limitation, not a passed fault-injection test.

The Spanish UI attempt is recorded separately in
`spanish-runner-failure-prior-source.json`. CoreSimulator failed to install the
application before XCTest launched because the InstallCoordination placeholder
promise UUID was missing. The source predates this folder's product SHA; no
Spanish UI result or screenshot is claimed for `6a69f3e`.

## Exact-source capture details

- Result bundle: `/Users/jmr.pineda/Library/Developer/XcodeBuildMCP/workspaces/LeonardoMD-586d26453937/result-bundles/test_sim_2026-11-16T16-10-52-164Z_pid5041_bae6fdc8.xcresult`
- Test: `PairingUITests/testMacRequestedRubricCaptureTerminalRetryBlocksAndLogsInEnglish()`
- Simulator: `5B689430-FDBD-44C0-A732-BE3C063F9403`, iPhone 17 Pro, iOS 26.5 (23F77)
- Screenshots: 1206 × 2622 pixels, 402 × 874 points
- Test-owned simulator was shut down after collection. The pre-existing E204 simulator, its app process and Device Hub process were left running.
- XCTest attachment timestamps are UTC: 503 at `2026-11-16T16:11:29Z`, 413 at `2026-11-16T16:11:46Z`, terminal 409 at `2026-11-16T16:11:55Z`.

See `manifest.json` for hashes, result metadata and evidence file mapping.
