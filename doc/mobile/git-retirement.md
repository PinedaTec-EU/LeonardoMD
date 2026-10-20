# Mobile Git retirement

Tracking: [#249](https://github.com/PinedaTec-EU/LeonardoMD/issues/249). Product decision: [ADR PR #246](https://github.com/PinedaTec-EU/LeonardoMD/pull/246).

Little Leonardo is a read-only companion. Pair with a desktop, approve explicit project grants, refresh authorized documents/resources and read the downloaded corpus offline. Editing, form changes, document creation/deletion and Git connection/publication are unavailable on iOS. Synchronization runs manually or at the configured interval while the app is active.

macOS retains its installed-system-Git tools and editable direct desktop synchronization, including offline copies, manual conflict review and exact receipts. Neither requires the removed mobile Git engine. Windows remains roadmap work and needs separate protocol/platform acceptance; this change does not implement Windows.

## Recover older mobile work

Previously downloaded Git projects appear as read-only recovery archives. Their original base, current files, previously sent files and published revision remain in the existing corpus archive. They are not refreshed, sent, relabeled as integrated or deleted during a direct-cache revocation. A UUID collision with a new direct grant fails rather than overwriting recovery data.

Open an old project and choose **Exportar recuperación**. Save its JSON file to a destination of your choice and transfer it to a desktop. The `project.files` entries contain the current documents/resources (base64 content); `project.base.files` and `project.publishedFiles` retain comparison copies. A path present in a comparison copy and absent from current files represents a deletion. Compare these versions manually against the desktop before applying changes. Preserve the original export until the result is verified. The export contains document content and should be handled like the original documents; credentials and connection configuration are excluded.

Old Git connection/baseline/publication metadata, Keychain items and remote device branches are not automatically deleted. They are no longer used for network operations by this app. Already sent commits remain in the remote repository and can be recovered using normal Git tooling. Export does not claim that those commits were integrated. This release does not include an automatic recovery importer or resume an old publication.

## Removed responsibilities

`LeonardoGit`, its pack/object/transport implementation, mobile SSH/HTTPS Git credentials/enrollment, native publication review and Git wakeup endpoints are removed. SSH/NIO/Swift Crypto package dependencies used exclusively by that module are removed. Built-in platform cryptography and TLS for direct pairing remain.

The retired Git wakeup route returns an unsupported-route response. Authorized desktop proposals continue through the existing direct-sync routes; read-only paired credentials cannot submit them. Existing mobile direct enrollment is explicitly read-only. No automatic grant elevation is introduced.
