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

Readiness completion is lifecycle-owned: one startup refresh now performs bounded
compatible-health confirmation after registration without Preferences. Five probes
with250ms async pauses are default; tests inject controlled pauses. No repeated
registration inside probing. Explicit disable invalidates held startup replies.
A newer healthy refresh owns displayed metadata; older readiness replies do not
overwrite it or spuriously reject healthy peer operations. Full770XCTest/39skips
plus72SwiftTesting pass. Current native evidence/input mapping is autonomous-*.

## Integration after project identities (#400)

PR #413 now includes main `54c00e42` and Guide45, preserving both feature help
sections. Fresh process PID16185 passed bilingual real Help and practice checks,
with originals/preferences restored and helper48295 untouched. Full integrated
779 XCTest checks (41 skipped), 72 Swift Testing checks, generic iOS build and
three deterministic guide checks passed. Current evidence: `doc/validation/helper-upgrade/candidate-help45/`.

## Signed 1270 recurrence and pre-install correction

The installed 1215→1270 update failed automatic renewal: old helper PID48295
remained registered and macOS rejected authenticated XPC with -67065. Three
device grants, project selections and TLS bytes were preserved. Evidence is
canonical in issue412 comment6775868256. Do not relabel that run as PASS.

The follow-up parks the helper through authenticated reload/drain and unregister
BEFORE Sparkle receives an actual Install reply. Download approval alone does
not pause sharing. A durable token preserves existing consent for the next
process; the old process cannot poll/re-register while installation is prepared.
Cancelled quit/installer abort restores through the normal lifecycle. Explicit
disable still cancels consent. Unknown live helpers retain the lifetime-lock
barrier and veto installation rather than being forcibly stopped. First-health
failures receive bounded health-only retries, without assuming an unknown helper
is older or safe to unregister. This applies to updates initiated by a source
version containing the preparation; external bundle replacement is not covered.

Owner declined logout/recovery of the existing unreachable1215 on 2026-11-10.
Keep that installed process and stores intact. Signed two-candidate A→B testing,
fresh packaged Help51 and iPhone access acceptance remain pending; do not close
412 on automated tests alone.

Pre-install preparation also preserves a newer helper registered from another
bundle without touching consent. A newer helper backed by the bundle being
replaced blocks installation. Initial authenticated identity failure blocks
preparation before preference changes; it never assumes that helper is older.

Synchronization preferences preserve the previous helper error while a health
query is in flight. The common switch preserves its previous indicator during checking,
shows green when online and red when unavailable, and hides it when disabled;
the status remains available to assistive technology. While the service is in an
error state, preferences retry health at a bounded interval; a change in local
addresses refreshes the sharing endpoint and discards an obsolete invitation.
Approval changes are reconciled when the app becomes active. See
`SyncHelperPreferencesSection` and `SyncHelperController`.
