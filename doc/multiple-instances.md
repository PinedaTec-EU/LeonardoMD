# Multiple instances on macOS

LeonardoMD uses a single process by default. In Preferences → General → On this Mac,
turn on **Allow multiple instances**, then choose **File → New instance**. Each
additional instance has its own windows and editor sessions. Turning the preference
off disables future additional launches; existing instances stay open.

Ordinary launches and Finder opens go to the principal instance. An additional
instance forwards external opens to it, even if macOS delivers the event to that
additional process. If the principal has exited, the receiving instance attempts
the same kernel-backed election and becomes principal if it wins. The explicit
`--new-instance` argument still requires the preference; without a running principal,
a launch becomes principal rather than an orphaned additional process.

Documents and project trees belong exclusively to one process. Case variants on
case-insensitive volumes share the same reservation, including future files. A file, its aliases,
or overlapping project folders cannot be opened in another instance while that
process owns them. Close the owning **instance**, not just its tab, to release the
reservation. Reservations deliberately survive navigation/tab closure to protect
in-flight file operations and package cleanup. The kernel releases them on process
exit or crash; abandoned metadata does not retain ownership. Separate projects and
documents can be opened independently, including projects in sibling folders.
Opening a project reserves its root; file mutations reserve their affected paths. This coordination protects cooperating
LeonardoMD processes on this Mac; external editors still use the existing conflict
checks and other Macs do not share the local ownership registry.

Only the principal starts synchronization services, peer-cache operations and the
updater. Their preferences explain this in additional instances. Synced source roots
and the linked-Mac cache are reserved by the principal before use; a conflicting
reservation prevents service startup instead of allowing concurrent mutation.
Portable global/project settings retain their existing changed-field merge and now
serialize the complete read/merge/write transaction across processes. Recents merge
independent additions; simultaneous changes to the same setting use the last writer.

Tracking: [#263](https://github.com/PinedaTec-EU/LeonardoMD/issues/263).

## Installing updates

The principal process owns Sparkle. Automatic checks remain available, while
downloads require user approval. Before approving a download, LeonardoMD requests
ordinary Quit in every other LeonardoMD application in the user's login session,
across bundle copies, and waits for observed process exit. This happens before
Sparkle creates its installer: Sparkle 2.9.6 monitors only one process, so leaving
an additional process alive when it chooses that target would be unsafe.

The principal remains editable during download. Its ordinary close preparation
still flushes previews, waits for Git/file operations and offers Save/Discard/Cancel
when installation requests Quit. A cancelled primary quit leaves that process
alive, so Sparkle cannot finalize by observing an additional instance exit first.
The final termination guard also checks for late processes from legacy copies.

Discovery and quit/status IPC use PID plus launch date. Missing identity,
replacement processes, rejected quit requests, cancellation and a 60-second peer
timeout prevent approval. Identified Preferences sheets can be dismissed; unrelated
modal decisions remain open. A nested palette editor or file chooser preserves
the entire Preferences presentation and its unapplied changes. Quit can be retried
after resolving a modal block. Older processes receive ordinary AppKit Quit.

An exclusive process lock prevents new participating processes from launching
while the approved candidate can create or retain an installer, including a
deferred update or cancelled primary Quit. Concurrent ordinary startups share the
same lock briefly during registration. Failed initial preflight releases it;
Skip, download cancellation before extraction or a confirmed no-update result
resolves the candidate and releases it. Process exit also releases kernel ownership. Already closed instances
remain closed; an outstanding ordinary quit request can still finish later.

A restored staged update with no verified single-process preflight is cancelled with
Sparkle's Skip response before peer closure; a fresh check can start a protected
download. Already armed helpers from legacy builds cannot be retrofitted by new
application code. Legacy copies do not honor the launch lock. Signed hosted
update/relaunch acceptance remains tracked in
[issue #202](https://github.com/PinedaTec-EU/LeonardoMD/issues/202).
