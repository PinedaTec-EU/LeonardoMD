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
documents can be opened independently, including sibling projects in one workspace.
Browsing a workspace does not reserve its entire tree; project/file mutations do. This coordination protects cooperating
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

The principal process owns Sparkle. Before an installation can terminate it,
all of its document windows complete the ordinary close preparation (including
preview flush, Git/file operations, and Save/Discard/Cancel). It then requests
ordinary Quit in every other running LeonardoMD application, across bundle
copies, and waits for observed process exit. A peer's cancellation, rejected
quit request, a new process, or a 60-second peer timeout cancels the current
installation attempt and releases the principal's prepared documents. Already
closed instances remain closed. Pending quit requests in other processes can
still complete; cancellation never forces a process to exit.

The installer dismisses only identified Preferences sheets. Document decisions,
Git sheets and file choosers retain their normal behavior. If Preferences has
a nested sheet (such as a palette with unapplied changes), the entire
presentation stays open and blocks termination until the user resolves it. Updated processes
report a cancelled quit through per-process IPC; older processes receive ordinary
AppKit Quit and can require manual Preferences dismissal. Their refusal or lack
of exit also prevents installation. A downloaded update may remain pending in
Sparkle for a later retry or ordinary Quit; every such attempt repeats the
all-instance guard.

A product-wide advisory lock excludes new launches while the principal waits
for other processes and until it exits. Concurrent startups briefly share the same lock
while registering its quit endpoint. Legacy builds predating this protocol do
not honor the launch gate; a newly observed process cancels the attempt. Hosted
signed update/relaunch acceptance remains tracked in
[issue #202](https://github.com/PinedaTec-EU/LeonardoMD/issues/202).
