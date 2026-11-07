# Helper consultation correction

Issue [#394](https://github.com/PinedaTec-EU/LeonardoMD/issues/394),
PR [#398](https://github.com/PinedaTec-EU/LeonardoMD/pull/398).

The suspended-settings regression fails with the previous `guard !configuring`
reload behavior: a concurrent read immediately returns busy instead of waiting.
The corrected helper uses a FIFO barrier and each queued command re-reads consent.
Cancellation skips that command's configuration read and releases its turn.
The poll runner is read-only and always receives the same UUID; one transient
failure recovers automatically, four consecutive failures surface the original
error, and cancellation neither retries nor delivers. No retry path invokes create.

The owning source commit introduced only these recovery internals, not UI controls
or a new help workflow. The public preferences-read port allows a real suspended
boundary in the helper test. Production still uses ConfigurationStore.

Focused5/5 and complete tests are recorded in validation.json. Runtime physical
acceptance belongs to the combined signed main candidate, not this isolated branch
or the older physical result recovered with manual Retry. Do not infer the numeric
NSError mapping or claim every cause of the original delayed alert is reproduced.
The transport candidate's tested original TLS behavior and current helper26651
remain untouched during these local checks. No private drawing or pairing payload
is committed. Existing manual Retry remains available for persistent errors.
