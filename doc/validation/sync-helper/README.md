# Sync helper validation

## Owner-authorized installed-service acceptance

Source: `5858c47a9762ba6567a7589721bfba71afbbfdb1`. An immutable Developer ID
signed QA copy was launched as a fresh native app; the installed app was not
replaced. `native-acceptance.json` and `registered-consumer-test.log` record the
real SMAppService registration, native owner consent and pinned loopback reader.

The reader test passes in 194.719 seconds:

1. The app displays the running helper and a synthetic project sharing only
   `note.md` on 127.0.0.1. Independent comparison codes match; only that project
   is visibly approved for the synthetic reader.
2. The pinned reader downloads the expected saved bytes and no siblings/drafts.
3. Owner editor PID 97372 closes normally; helper PID 97630 remains, and the
   reader downloads the document again without that owner editor.
4. SIGTERM stops only the helper; launchd autonomously restarts it as PID 3108.
   The same pinned identity and granted reader download again without reopening
   the owner editor.
5. The reopened editor disables the helper. The listener/launch job disappear,
   a transfer is rejected while the editor stays open, and Linked Macs shows
   offline with its linking action disabled.

The installed executable hash remains unchanged. The test service is removed,
original mobile preferences/store are restored, other current global preference
fields are preserved under the canonical process lock, and the newly created
TLS Keychain item is removed after metadata established test ownership. An
unrelated QA process later held primary ownership; attempting to reopen the
installed app forwarded rather than proving a new installed-app window. That
unrelated process was not terminated.

Physical two-Mac/VPN networking, a hardware logout/reboot cycle, an in-place app
upgrade and approval of legacy Keychain ACLs are not claimed. RunAtLoad/KeepAlive
are configured, and real autonomous helper restart/reuse is exercised.

## Regressions discovered during acceptance

- #324/#325: signing only a hardened main/helper left Sparkle with an incompatible
  nested signature. Static deep verification accepted it; the first app launch
  failed. Existing inside-out release signing opens a real first window. The QA
  verifier now rejects mismatched nested teams. `qa-startup-signature.json` retains
  the sanitized diagnostic, not the owner's full report.
- #327: launchd supplies a relative program/argv. The helper now obtains its
  actual executable location from the kernel, preserving signing checks, and
  logs/exits cleanly on startup failure.
- #321: an active write must finish before unregistering. A dead helper can be
  unregistered only while owning its startup lock; this proves no active helper
  write and blocks a concurrent restart. Both branches have regressions.
- Rebuilding a registered development path produced stale OS launch constraints.
  Unregistration and a complete immutable signed copy recovered without global
  BTM resets or weaker security. Unregister before replacing a QA bundle.

## Component captures

Original English/Spanish production-control captures and canonical sidecars are
archived byte-for-byte under `accepted-component-capture/{en,es}/` as
`mobile-helper-v8` and `macs-helper-v8`. Capture
source is `0c46b98e85092f5ef169fa6823935f04db200c2c`; native viewports are 560×660
and 560×650 points, with exact pixels/times/hashes in the sidecars. These show
isolated synthetic disabled settings and disabled network actions, without
registration or real-device pairing. At the #319 native acceptance checkpoint, those production view/localization
files and disabled-state inputs remained unchanged; later #337 intentionally
reorganizes these controls. Current role-page originals live in
`doc/guide/{en,es}/assets/sync-sharing-v12.*` and `sync-connections-v12.*`.

`prior-component-capture` retains the earlier `4628783b…` originals; `previous-guide`
retains superseded guide screenshots. No original was transformed or edited.
Guide v10 packaged the accepted `0c46b98e…` controls alongside the inspector help;
Guide v13 uses the current #337 role-page captures. Live native AX inspection
established running, consent and disabled states; component captures do not
pretend to be fresh packaged startup screenshots.

Accepted historical originals (their adjacent sidecars retain original capture facts):

- [Sharing controls, English](accepted-component-capture/en/mobile-helper-v8.png)
- [Sharing controls, Spanish](accepted-component-capture/es/mobile-helper-v8.png)
- [Client controls, English](accepted-component-capture/en/macs-helper-v8.png)
- [Client controls, Spanish](accepted-component-capture/es/macs-helper-v8.png)

## Local and hosted validation

- Final local suite: 618 XCTest cases, 34 opt-in skips, zero failures; 28 Swift
  Testing cases also pass. The real registered consumer was additionally run
  explicitly and passed.
- Scripts: 56 cases (7 platform/environment skips); plugin: 38; packaging: 20.
- Release-mode packaging, strict/deep signing, nested-team/launch-plist/helper
  dependency inspection and real mutually authenticated XPC pass. The local
  package is not an official published/notarized release.
- Exact-head CI and independent judgment are recorded on PR #320, separately
  from this evidence. No merge is implied by local validation.

The task's Launch Services registrations for its QA copies were removed and the
installed app's registration refreshed after cleanup; no unrelated QA app was
unregistered. `package-inspection.json` is the final static inspection collected
after native acceptance; its checkout differs from the native source only by
evidence/documentation. The signed executable hashes in native/signing manifests
bind the actual tested binaries.

## Integration refresh after graphic inspector PR #326

The main-branch inspector update added its own guide v8. This branch preserves
both sets of chapters, assets and inspector image sizing and regenerates guide
v9 with a separate personal-copy directory. The native registered-helper
acceptance above remains for source `5858c47a9762ba6567a7589721bfba71afbbfdb1`;
the merge changes unrelated inspector code and guide packaging, not helper
runtime or its captured preferences. Fresh compiled tests and hosted CI validate
the combined head. No new native guide-window inspection is claimed while the
Mac is locked. The installed original app was subsequently reopened successfully
to its Home window after the earlier primary-owner forwarding limitation.

## Lifecycle health regressions (#331 / #332)

The registration controller distinguishes enabled-but-missing/error registration
from disabled consent, clears superseded diagnostics and rejects late status
responses after a consent change. Regression fixtures cover both Service
Management statuses, recovery and an explicitly held status reply during disable.
The host now reads actual listener readiness instead of caching object existence.
An injected listener deterministically fails after startup, refuses its first
restart and then recovers; tests require no stale success and retained TLS identity.
These fixtures do not claim a physical interface-failure native acceptance run.
The existing bilingual help already documents unavailable/disabled states and
network recovery; these fixes enforce that documented behavior without new controls.

The subsequent #331/#332 source changes extend the earlier native acceptance
with listener readiness and status-generation guards. The historical registered
service run is not presented as an exact-head physical failure test; fresh full
and focused tests exercise these corrections, including real loopback TLS
readiness before startup, after startup and after stop.

## Integration refresh after agent import PR #330 (issue #329)

Main's standalone agent-import guide and File menu entry are retained. The main
help combines both source bodies, inspector image layout and sync instructions,
then advances to Guide v10 and a separate personal-copy directory preserving
v9 annotations. Helper production code is unchanged from `001fa216a49030deee4853f6b0add58e0ecc3762`.
The historical 618-case record above describes the earlier native acceptance
checkpoint; subsequent full-suite counts are recorded separately.

### Compilation accounting reconciliation

A read-only review at `001fa216a49030deee4853f6b0add58e0ecc3762` actually ran four
successful compiler-bearing commands via `compile-and-record.py`, restoring
the tracked delta after each command. The allocations must not be discarded:
four build counts are restored here (22 → 26) before subsequent successful
compilations. The commands were `swift test --filter` for the uncertain-stop
case, `SyncHelperControllerTests`, `SyncHelperHostTests`, and full `swift test`.
Later review replays use `--skip-build`; any needed compiler-bearing validation
must be run by the owner of the branch through the recorder and preserved.

### Combined guide image budget (#333)

The first combined guide failed twice on `document.images[14].naturalWidth > 0`;
the native image subsystem reported `image_load_rejected category=documentLimit`.
All referenced assets were present. Generated diagrams now declare 720×160
intrinsic dimensions with the original 1080×240 viewBox, preserving vector
fidelity and original PNG captures while respecting the existing preview budget.
All five `BundledUserGuideTests` then pass, including complete native image
loading in both locales and the standalone agent-import guide. No renderer
limit was raised.

Final combined-help validation: 625 XCTest cases (34 optional skips), 28 Swift
Testing cases and 56 script cases (7 skips) pass. The last compiled guide-only
run passes all five tests with the standalone AgentImport v1 archives restored
byte-for-byte to main. The compact vector option applies only to main-help
illustrations; the standalone published guide revision remains unchanged.
