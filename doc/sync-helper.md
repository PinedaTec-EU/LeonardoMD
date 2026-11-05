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
the agent. Failed unregistration cannot restore consent on a later restart.
The helper rechecks configuration for each control request and periodically while
idle; failed startup/network selection retries without reopening the editor.

## Local control and write completion

The agent advertises `eu.pinedatec.LeonardoMD.sync-helper` in the user's bootstrap
domain. XPC checks the caller's user ID and the packaged app's designated code
requirement before accepting control. The client likewise pins the packaged
helper's designated requirement. Developer ID builds retain signing identity
across updates; ad-hoc QA code remains bound to its exact signature. There are
no unsigned/development bypasses. Signing happens inside out before sealing the
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

Tests cover isolated host configuration, real pinned HTTPS saved/scope transfers,
disable/restart identity and grant persistence, lifecycle approval/health/failure,
stale-form protection, outbound denial and the lost-reply application barrier.
These compose production components; they do not prove installation with
`SMAppService`, Keychain approval on an existing installation, fresh packaged
startup, physical two-Mac networking or a real logout/reboot/login cycle.

Fresh packaged acceptance must use the real app bundle and respect the running
user instance. In particular, do not close a user's editor or register a QA
helper over an existing service silently. Release readiness requires recording
that installation/lifecycle evidence on #319 and its PR.
