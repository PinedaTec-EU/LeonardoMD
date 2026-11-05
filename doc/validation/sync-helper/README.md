# Sync helper evidence

Source UI captures: `4628783b0dd892a7ca1861849688d12f9aa80147`.
The production `SyncHelperPreferencesSection`, Little Leonardo and Linked Macs
views were compiled from that source. Original English/Spanish PNGs, capture
contexts and canonical metadata are in `doc/guide/{en,es}/assets/` with the
`mobile-helper-v8` and `macs-helper-v8` names. They show synthetic isolated
configuration, a packaged-helper-present fixture with the master disabled, and
network actions disabled. No device pairing or service registration occurred.
Native viewports are 560×660 and 560×650 points; pixels are recorded in sidecars.

The historical guide screenshots and their original sidecars are retained in
`previous-guide/{en,es}`; they are no longer packaged as unused guide assets.
Guide v8 packages the newly captured production controls.

Subsequent documentation/package/evidence and test changes do not change the
captured SwiftUI production controls. This evidence is component rendering,
not fresh packaged startup, Service Management installation, Keychain migration,
or reboot/login acceptance. Those gates remain open under issue #319.

## Local checks

- Full suite: 614 XCTest cases, 33 opt-in skips, zero failures, plus 28 passing Swift Testing cases.
- Scripts: 54 cases (7 platform/environment skips); plugin: 38; packaging: 20.
- A final source refresh imported only main's version-materialization metadata; three affected release-change tests pass.
- The release-mode local QA bundle passes strict/deep signature verification, helper launch/dependency inspection and both mutual Developer ID requirement checks. See `signed-package.json` and `package-inspection.json`.
- The signed QA package is retained at the task worktree's `output/LeonardoMD.app`. It is not an official published/notarized release and has not been installed or registered.

Source and privacy limits above remain applicable. Real installed-service acceptance and fresh independent judgment are pending.
