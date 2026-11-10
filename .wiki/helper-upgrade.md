# Synchronization helper upgrade

Canonical bug: [#412](https://github.com/PinedaTec-EU/LeonardoMD/issues/412).
Corrective PR: [#413](https://github.com/PinedaTec-EU/LeonardoMD/pull/413).

The independent launchd helper survives closing/updating the editor. Enabled
registration and healthy legacy XPC do not prove it runs the installed build.
1215 source-update errors were caused by1136 still serving; normal master OFF/ON
loaded installed1215 and owner confirmed paired project/file access without pairing.

The corrective candidate captures build/bundle identity once at helper launch,
adds it compatibly to authenticated health, and renews older/obsolete registration
through existing safe stop/unregister barriers. Never downgrade a newer helper.
A durable preferences upgrade token temporarily denies helper work while retaining
existing consent across failure/crash. Atomic manual consent clears that token,
so late upgrade completion cannot re-enable a user-disabled service. Existing
pairings, source selection, TLS identity and pending application leases remain owned
by their current stores. Missing/newer health stays separate from operational readiness.

Guide40 is reserved for413; personal34/35/36/37 already exist from other work and
must not be overwritten. Compare actual bundled/personal hashes before acceptance.

Late health replies also retain transaction ownership: when another store replaces
or completes the upgrade token, the stale controller reloads current intent without
clearing that token, disabling consent, or unregistering the renewed helper. Two
deterministic regressions failed with four assertions before this correction and
pass after it; the focused controller/core/identity suite passes (24 tests, one
opt-in native capture skipped).

Integrated main1233 (#408) before final validation. Guide40 packaged Help passed
in fresh PID65363 in both locales, practice originals restored, helper48295
preserved. Full integrated suite760XCTest/39skips plus72SwiftTesting and iOS
Simulator compilation passed. Evidence and explicit signed-runtime limitation
are in doc/validation/helper-upgrade/README.md.

Final retry refinement injects a main-actor clock (default Date.init) and names
the existing30-second interval. Deterministic29/30-second retry test passes; full
suite761XCTest/39skips+72SwiftTesting passes. Controller component captures were
renewed; exact unchanged Help/renderer input mapping preserves packaged Help40
acceptance without relabeling the older executable.

Activation/readiness follow-up: enabled legacy registration is reconciled from
setEnabled(true); peer adapters explicitly use their actual shared helper. The
static legacy gate is removed. Fresh identity, starting/busy state, durable token
and consent re-read prevent first requests during renewal. Four real regressions
failed with12assertions before correction; full766XCTest/39skips+72SwiftTesting
pass afterward. Current native components and unchanged Help inputs are recorded
in readiness-input-mapping.json.
