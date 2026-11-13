# PR #428 — Automatic consent-poll error recovery

- **Source fix:** `c9d8c53cea8ec437be5e62a6c2e7101b0c0051ea`
- **Issue:** [#421](https://github.com/PinedaTec-EU/LeonardoMD/issues/421)
- **PR:** [#428](https://github.com/PinedaTec-EU/LeonardoMD/pull/428)

## Behavior covered

The Share from this Mac Preferences view polls consent every two seconds. A
single failed automatic consent read is now provisional while helper health is
checked. A second consecutive failed read reports one automatic diagnostic for
that failure episode. A successful read clears only the automatic diagnostic;
an error from an explicit user action remains visible. Dismissing an automatic
diagnostic does not make the same failure episode present it again.

## Focused validation

Recorded command:

```sh
python3 scripts/compile-and-record.py --pr-number 428 -- swift test --filter SyncHelperControllerTests/testConsentFailureChecksHealthOncePerFailureEpisode
```

Result: **1 test passed, 0 failures**. The regression holds the helper recovery
status call and asserts the alert-bound `controller.error` is nil while recovery
is pending and after the first failed poll. It then verifies the persistent
failure, recovery clearing, one-time dismissal behavior and preservation of an
explicit action error.

The successful compiler-bearing invocation is recorded in
`deploy/version/entries/428.yaml` as build delta **186**. `git diff --check`
passes. Exact-head CI and strict review run after this source commit and its
evidence update are pushed.

## Evidence scope

The [v39 native Preferences captures](../428-quiet-status-v39/README.md) remain
bound to product/test source `9c970868ebcc53180867a12853cf9aa078b164d1`. They
cover status and layout states that this fix does not change; they do not depict
the transient consent-poll alert. This regression is evidenced by the controlled
runtime/helper test above. No new screenshot from a running application is
available for the transient failure state.

The [v40 packaged Help record](../428-quiet-status-v40/README.md) remains the
current bilingual Guide v59 and practice-form acceptance. This fix changes
automatic error timing, not guide instructions or controls, so no bundled-help
source or package changed.

Hosted beta install, update and relaunch acceptance remain pending until the
candidate is published.
