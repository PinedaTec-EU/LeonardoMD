# Little Leonardo

Implementation tracking: [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92).

## Agreed product contract

Each project chooses direct read-only synchronization or Git editing. Git projects may choose direct mode. Only the direct service requires the desktop and mobile to share a private local network; Git can operate over the Internet.

The desktop service is explicitly enabled, off by default. Pairing supports a unique QR or IP/port and a cross-checked code. Projects are explicitly authorized. Device credentials stay in platform secure storage, outside portable configuration. Turning off the service retains mobile corpus; revocation requests deletion on the next reachable contact and rejects further document access. Offline deletion cannot be guaranteed before contact. Git copies are independent of direct revocation.

Direct snapshots include permitted documents/resources and open unsaved buffers. Mobile caches them for offline reading and explains the Git requirement when Edit is pressed. Both manual synchronization and a configurable interval are available; intervals operate while the iOS app can execute, without promising continuous background timers.

Git import selects a folder before transferring file contents and remembers it. Sparse checkout alone is insufficient: partial transfer must be supported by both server and iOS adapter. Never fall back silently to full clone. Hidden files, credentials, build outputs and path escapes are excluded. Offline creation, editing and deletion remain inside the selected corpus.

Send changes publishes a device-specific branch before sending an optional paired-desktop notification. Publication and notification are separate outcomes. Desktop also discovers branches by fetching, offers diffs and user-controlled reconciliation, and preserves unsaved desktop work. Mobile distinguishes local changes, sent work and integrated work. Further offline edits survive incorporation of a previous send; overlapping edits remain pending for desktop resolution.

## Implementation status

`LeonardoSync` is an independent Foundation-only SwiftPM library targeting macOS 14 and iOS 17. It currently contains corpus path/content limits, direct read-only and Git-editable offline state, atomic cache persistence and a project corpus reader with unsaved-buffer overlays. Its regression tests cover escapes, hidden/build exclusions, symlinks, case aliases, size limits, restart, deletion and later edits during integration.

This is a foundation, not a working companion application. Network service, pairing, credential storage, revocation transport, native iOS UI, real Git adapter, desktop reconciliation interface and end-to-end evidence remain pending. No partial-clone support is claimed for an iOS Git library until demonstrated with a large-repository fixture.

## Boundaries to retain

- Selected scope governs reads, edits and publication, not just the mobile file browser.
- Publication must succeed before notification; notification delivery never substitutes for Git discovery.
- Integration updates must identify the published commit whose work was accepted, rather than trusting any new remote revision.
- Invalid or oversized snapshots fail atomically rather than silently delivering an incomplete corpus.
- Reconciliation must preserve local work; neither desktop buffers nor mobile edits are implicitly discarded.
