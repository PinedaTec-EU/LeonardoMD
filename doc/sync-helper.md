# macOS sync helper

Source work: [#319](https://github.com/PinedaTec-EU/LeonardoMD/issues/319).

LeonardoMD registers its bundled `LeonardoSyncHelper` as an optional per-user
LaunchAgent through `SMAppService`. It requires no administrator/root daemon.
The helper starts at login and `launchd` restarts it after process exit while
registered and permitted by macOS. This does not provide service before login,
wake a sleeping computer or guarantee network reachability.

## Ownership

- The app owns configuration and the installation/approval/enable UI. Its exit
  does not stop the registered helper. Additional app instances cannot control it.
- The helper owns `DesktopDirectRuntime`, the TLS listener, source identity,
  device consent, scoped saved-file snapshots, incoming proposals and receipts.
- The app owns explicit device approval and source reconciliation UI. Approved
  filesystem transactions execute in the helper while the app holds its editor
  lease. The helper never accepts a proposal without the owner's decisions.
- Desktop peer working copies and outbound orchestration remain in the app.
  Their remote adapter checks helper health and master consent before and after
  every network operation. Offline reading/editing remains available.

## Configuration and disabled state

The sole persisted configuration is
`~/Library/Application Support/LeonardoMD/preferences.json`, in `mobileSync`:
`helperEnabled` is the master device-sync consent; `enabled` separately permits
source sharing. The master defaults off, including for an existing installation.
Project selections, private-network policy and device grants remain intact.
Only the lifecycle UI changes the master; a stale sharing form cannot restore it.
ConfigurationStore merges the new field independently across processes/windows.

A running helper without source sharing is valid for outbound use. A disabled,
unregistered, approval-pending, missing or unreachable helper is offline even
while the editor is running. There is no in-process source-listener fallback.
Disabling first persists denial, asks the helper to reconcile it, then unregisters
the agent after graceful stop is acknowledged. An already approved transaction
finishes before that acknowledgement. An unavailable/failed acknowledgement
leaves denial persisted without forcibly killing an uncertain write. A dead
helper can be unregistered only while the app owns its process-wide startup
lock, proving no helper write is active and preventing a concurrent restart.
An alive helper retries configuration reconciliation. Failed unregistration cannot
restore consent on a later restart.
The helper rechecks configuration for each control request and periodically while
idle; failed startup/network selection retries without reopening the editor.

## Local control and write completion

The agent advertises `eu.pinedatec.LeonardoMD.sync-helper` in the user's bootstrap
domain. XPC checks the caller's user ID and the packaged app's designated code
requirement before accepting control. The client likewise pins the packaged
helper's designated requirement. Both sides require the expected signing
identifier and the same nonempty Developer ID team, preventing a copied helper
from trusting an unrelated parent app. Ad-hoc builds cannot enable the service;
there are no unsigned/development bypasses. Signing happens inside out before sealing the
app; package inspection verifies the helper, launch definition and dependencies.

XPC failure does not mean a remote write was canceled. Each owner application
has a private approval ticket and stable process lock under
`MobileSync/LocalApplications`. The helper must acquire that lock and consume the
ticket before applying. On any reply/error, the client revokes a queued ticket or
joins an active helper write before releasing its native editor lease. Stable
lock inodes remain for coordination; the small approval file is removed after
completion. Stale-comparison errors retain their typed native recovery path.

The existing pinned HTTPS, project scopes, revocation and manual three-way
reconciliation remain the network authorization boundary. Snapshots now contain
saved disk bytes only; unsaved editor buffers are local. Owner review still
captures local drafts and preserves them through the existing reconciliation lease.

## Validation boundaries

Owner-authorized native acceptance used an immutable Developer ID signed copy,
registered through the real app preferences, a synthetic loopback project and
an independently paired test reader. The source owner process exited; the same
pinned client still read saved bytes. launchd then restarted the helper after
SIGTERM, without reopening the source editor, and the same identity/grant read
succeeded. Disabling through the reopened editor unregistered the service and
rejected transfers while that editor remained open. Linked Macs showed offline
and disabled its network action. See [evidence](validation/sync-helper/README.md).

The original installed app binary was unchanged. Test service/state and the
new test-owned TLS Keychain item were removed, original mobile preferences/store
were restored, and other concurrently changed global preferences were preserved.
A separate QA process held product-wide primary ownership when reopening the
installed app was attempted; that unrelated process was not terminated.

This proves the installed per-user service lifecycle on this Mac, not physical
two-Mac/VPN networking, a hardware logout/reboot cycle, an in-place app upgrade,
or approval of a legacy app-created Keychain ACL. RunAtLoad/KeepAlive are configured
and automatic helper recovery is exercised. Existing TLS formats and grants are
retained; an OS credential-permission decision remains the user's responsibility.

Fresh packaged acceptance must use the real app bundle and respect any running
user instance. Never close the user's editor or register over an existing service
without authorization. Do not rebuild a registered QA bundle in place: unregister
first and test a complete, signed, immutable copy. Development-path churn was
observed to leave stale launch constraints; no global BTM/security reset was used.

## Signed local QA packages

The local build script emits an ad-hoc bundle. For Developer ID hardened QA,
use the same inside-out order as `scripts/prepare-release.sh`: sign the helper
with its fixed identifier, Sparkle's Downloader/Installer XPC services,
Autoupdate, Updater app, framework, then the main app. Signing only the helper
and main app can pass deep static verification but fail library validation at
startup. The package verifier now checks the nested signing teams as well.

The helper resolves its executable location through the kernel; a launchd
relative BundleProgram/argv is not a filesystem identity. Startup failures log
and exit cleanly rather than raising an unhandled Swift top-level error.
