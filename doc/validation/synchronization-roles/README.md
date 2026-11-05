# Synchronization by connection role (#337)

The native Preferences category now owns a single common Leonardo Sync control
above two pages: Share from this Mac and Connect to other computers. This is a
navigation/presentation change, not a migration of persisted preferences,
protocols, grants, invitation formats or offline copies. Source sharing remains
independent from client access. Both directions retain the existing helper and
review gates.

## Original component evidence

`captures/{sharing,connections}-{en,es}.png` show production components with
isolated empty configuration and disabled helper/sharing. Viewport: 532×490
native points, 1064×980 image pixels. They reproduce the Preferences content
width and test the two languages without touching the owner's settings.
`device-roles-{en,es}.png` shows the production identity rows with synthetic
names and explicit protocol capability kinds, not real paired devices.

Capture source is recorded in each original context and canonical metadata
sidecar. Later help/package/count/evidence changes do not alter these view
components. No browser/CSS engine exists for this native surface. Captures
illustrate initial states and capability labels; they do not establish a new
pairing, service registration, remote transfer or physical two-Mac acceptance.
The EN/ES sharing and connection originals are also the authored chapter 14–15
help illustrations; previous instructional images are replaced. Personal guides
stay untouched through the new Guide-v12 copy directory.

## Validation

`SynchronizationPreferencesTests` hosts each role page in both languages and
checks that showing them leaves the exact preferences bytes unchanged, helper
and sharing off, source listener absent, and remote connections/copies empty.
The opt-in capture output is enabled with `LEONARDO_SYNC_ROLES_EVIDENCE`;
`EVIDENCE_SHA` records the source. Run compiler-bearing validation through the
PR-bound recorder; read-only repetition may use `swift test --skip-build`.

Existing helper, stale-sharing-form, peer gating, pairing, grant persistence and
manual incoming-review tests cover the unchanged backend contracts. Full suite,
packaged first-window/navigation checks, current-head CI/judgment and beta
publication evidence are tracked on the canonical issue:
https://github.com/PinedaTec-EU/LeonardoMD/issues/337

Local intermediates are private to this worktree's `.build`; no external Swift
build path override is present. Aggregate task budget: 5 GiB; backing volume
had over 1 TiB free before compilation. Release archives are final deliverables,
not disposable intermediate caches.
