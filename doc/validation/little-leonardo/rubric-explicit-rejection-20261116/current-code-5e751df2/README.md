# Explicit rubric rejection evidence

This folder records a clean native UI run for PR #435 against product source
`5e751df2cccb8e9b9451c86175a5886e0a1f0aa6`. The English-locale retry test
passed 1/1 on an iPhone 17 Pro simulator running iOS 26.5. It exercised
recoverable HTTP 503, invalid-payload HTTP 413 and terminal HTTP 409 after a
deliberate manual retry.

The Mac fixture recorded response statuses `[503, 503, 413, 409]` with one
stable request ID. There was no automatic response replay after either 503 or
413. The 413 draft remained in `pendingSend`, retained its response and
required an explicit retry. The later HTTP 409 followed that deliberate retry.
See `manifest.json` and the fixture audit JSON files for the test and state
evidence.

The test passed its retry-behavior assertions, but its screenshot also exposed
a separate localization defect: the test launched with English locale
arguments, while rubric titles, form labels and controls still render in
Spanish. Only the error copy is English. This full-screen language mismatch is
tracked separately in [#462](https://github.com/PinedaTec-EU/LeonardoMD/issues/462)
and is not claimed as accepted here. It does not change the #458 result for
preserving an explicit rejection for manual retry.

At the time this UI test was captured, fresh packaged Help and practice-form
acceptance for Guide v88 was pending; that is the historical state recorded in
the attached test manifest, not a result of this UI run. A later fresh QA
process opened bundled Help in English and Spanish, inspected the required
examples and Math fallback, and saved/reopened both practice forms. The v88
acceptance (QA build 1602 and packaged resource hashes) is recorded in the
[PR #435 v88 acceptance comment](https://github.com/PinedaTec-EU/LeonardoMD/pull/435#issuecomment-6925088977).

The task-owned simulator was shut down and its test app and fixture listener
were stopped after capture. Pre-existing simulator E204 and its app and Device
Hub processes were left untouched. No private fixture TLS identity was copied
into this evidence folder.
