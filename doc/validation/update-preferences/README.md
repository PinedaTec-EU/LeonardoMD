# Preferences-originated update termination (#202)

The correction moves primary Preferences dismissal to the user-driver install
reply, before Sparkle requests AppKit termination. Download approval keeps the
primary Preferences open. Downloaded/resumed and ready-to-install paths dismiss
only the identified sheet. Nested palette/file decisions and unrelated Save/Git
sheets reject approval without discarding their state. Existing document/Git
quit checks and all-instance safety gates remain active.

Sparkle 2.9.6 `SPUCoreBasedUpdateDriver.m` calls `willInstallUpdate` from
`installerWillFinishInstallationAndRelaunch`; it is too late to unblock an
earlier termination request. The first approval boundary is in
`CoordinatedUpdateUserDriver.preparedChoice`. After a cancelled document quit,
Sparkle stores a separate retry-termination closure. The user driver wraps that
closure through the same preparation/dismissal gate; a retry does not call
`showReadyToInstallAndRelaunch` again.

Native outgoing acceptance passed on 2026-11-05 (see `native-acceptance.json`). It runs from the corrected binary,
not merely update an unchanged old app into a corrected target. The four
changed production files are identical between public source v0.1.797 and the
current base before this patch. A disposable v0.1.797 source fixture can apply
exactly this patch (with matching production-file hashes) and update through
real Sparkle to an already published newer signed/notarized beta. Its canonical
baseline version stays unchanged; this is a local backport test fixture, not a
new public release or version allocation. Compiler-bearing fixture validation
is charged to this PR's owning worktree. Preserve signatures, real executable
and resources; never install over the owner's application or force Quit.

## Author-owned native component captures

`captures/component-{en,es}-{beta,deferred}.png` are original production
UpdatePreferencesView captures at source `9be0db7`, with isolated defaults and
a fake updater. They show the unchanged fields and the pending-update channel
guard; they do not prove network/install/relaunch. Context timestamps and native
532×550-point viewports were measured during capture; canonical sidecars bind
the 1064×1100-pixel originals. Native AppKit/SwiftUI has no browser/CSS engine.
Actual outgoing installation is a separate real-process acceptance below.

## Actual outgoing acceptance

The final four production files at `93ced7788fb7bf7d649abe082f5842288a8aa26d`
were copied byte-for-byte into the public v0.1.797 baseline. The test-only
bundle beta-feed field points to the official archived v0.2.826 appcast:
the latest v0.2.829 canonical ZIP URL returned HTTP 504 in two real Sparkle
attempts. No public feed was changed. The final fixture was Developer ID signed,
notarized, stapled and assessed by Gatekeeper after that metadata change.

- Saved document: Preferences → Updates → Check now → Install Update →
  Install and Relaunch. Source PID 94156 exited; beta PID 95433 reopened
  automatically, reporting 0.2.826/826. Its first native window was observed.
  The synthetic document SHA-256 stayed unchanged.
- Unsaved document: the same flow dismissed Preferences and presented
  Save/Discard/Cancel. Cancel retained source PID 92473, its unsaved marker and
  the original disk hash. After Save, reopening Preferences → Check now →
  Install and Relaunch invoked the separate retry path. Target PID 93794 opened
  automatically with the saved marker present on disk and version 0.2.826/826.
- Neither final installation used Done, Cmd-Q, a forced exit or an external
  launch to make it complete. Target PIDs/version were recorded before CUA
  rebound to the already-running target. Normal Quit happened only after
  verifying target readiness, to proceed to the next isolated trial.
- `/Applications/LeonardoMD.app` remained 0.1.797 with its original executable
  hash. Its prior document was reopened read-only. Temporary Launch Services
  registrations were removed and the original app registered again. The exact
  pre-test release-notes presentation value was restored; no whole-preferences
  import was used. Device sharing/helper stayed disabled.

The first patch passed direct installation but failed cancel/save/retry because
Sparkle bypasses the original install reply on retry. That observation produced
the additional wrapper and two regressions, followed by both final trials above.
Updating *into* a fixed target still does not exercise its outgoing termination
implementation; the archived target is not claimed to contain this fix.

Full local validation of the final code: 631 XCTest cases (34 optional skips),
28 Swift Testing cases; six focused Preferences installation regressions pass.
The full suite includes real WKWebView rendering of both packaged help locales,
all fifteen images and interactive examples, plus preservation of personal
practice answers. The previous unchanged Python suite passed 93 tests (7 skips).
Five successful compiler invocations are retained in PR 336's ledger; the
cancelled command that was waiting on a build lock is not counted.

The component captures remain valid for unchanged UpdatePreferencesView: later
commits change termination behavior, counters and evidence, not its layout.
