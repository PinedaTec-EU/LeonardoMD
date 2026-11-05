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
in `doc/guide/{en,es}/assets/` as `mobile-helper-v8` and `macs-helper-v8`. Capture
source is `0c46b98e85092f5ef169fa6823935f04db200c2c`; native viewports are 560×660
and 560×650 points, with exact pixels/times/hashes in the sidecars. These show
isolated synthetic disabled settings and disabled network actions, without
registration or real-device pairing. Production view/localization files and
captured disabled-state inputs remain unchanged through native acceptance;
later changes concern startup/registration/shutdown and QA verification.

`prior-component-capture` retains the preceding originals; `previous-guide`
retains superseded guide screenshots. No original was transformed or edited.
Guide v8 packages the new production-control captures. Live native AX inspection
established running, consent and disabled states; component captures do not
pretend to be fresh packaged startup screenshots.

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
