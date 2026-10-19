# Preferences scope native QA

Tracking: [issue #173](https://github.com/PinedaTec-EU/LeonardoMD/issues/173), [PR #174](https://github.com/PinedaTec-EU/LeonardoMD/pull/174).

Captured 2026-10-19, Europe/Madrid, using CUA on the real locally signed packaged LeonardoMD QA process. The prepared app was built from source checkpoint `7f8a888b925a21b296070c9fe4f78e343c183313`; subsequent changes in this PR only publish evidence and documentation. Bundle version remains the base ledger's 0.1.405; it is not a newly published release. The exact source tree and final reviewed head are recorded in the PR evidence comment.

All native `.png` captures are 1160 × 1240 pixels for the original 580 × 620 point sheet at 2× density, using a synthetic temporary project. `design-target.png` is generated concept 2, not bug/implementation evidence. `target-normalized.png`, `design-comparison.png`, `scope-comparison.png` and `navigation-comparison.png` are explicitly derived comparison boards; original captures are preserved separately.

See [the QA report](../../../design-qa.md) for normalization, intentional corrections, tested states, startup evidence and remaining delivery limits.

For repeat captures with Stage Manager active, choose **Window → Bring all to front** in the QA application before opening Preferences. The app action activates the process; raising a window alone can leave a tilted thumbnail in the capture. Never disable the user's window-management settings to work around this.
