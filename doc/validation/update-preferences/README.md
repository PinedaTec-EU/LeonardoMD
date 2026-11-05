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
`CoordinatedUpdateUserDriver.preparedChoice`.

Native outgoing acceptance is pending. It must run from the corrected binary,
not merely update an unchanged old app into a corrected target. The four
changed production files are identical between public source v0.1.797 and the
current base before this patch. A disposable v0.1.797 source fixture can apply
exactly this patch (with matching production-file hashes) and update through
real Sparkle to an already published newer signed/notarized beta. Its canonical
baseline version stays unchanged; this is a local backport test fixture, not a
new public release or version allocation. Compiler-bearing fixture validation
is charged to this PR's owning worktree. Preserve signatures, real executable
and resources; never install over the owner's application or force Quit.
