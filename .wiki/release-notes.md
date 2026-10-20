# Native release notes

Central optional summaries and `changes_output_path` own generated change data;
Leonardo packages the byte-identical JSON and validates version/source arithmetic
at load. The native controller runs once per primary startup after Finder opens,
then continues default-app prompting after dismissal. The per-version suppression
switch defaults on; manual app-menu access bypasses automatic suppression.
Preferences preserve the interval for repeated notices and label unknown/earlier
version history. Tests cover offline identity/history rejection, preferences,
startup continuation/manual reopening, the checked-in artifact, and native en/es light/dark interval/downgrade captures.
CI publishes `release-notes-package-<SHA>` with executable/dependency inspection,
signature verification, canonical bundle/version identity and artifact byte/hash comparison.
See [release contract](../doc/release-version-ledger.md#native-release-notes).
Tracking: [#209](https://github.com/PinedaTec-EU/LeonardoMD/issues/209).

Integrated engine: `d5bf9cbf0b5a2c92dfb6fafa24e718fa3fcedebe` ([central #324](https://github.com/PinedaTec-EU/pinedatec-ci/pull/324)); central catalog activation: [#327](https://github.com/PinedaTec-EU/pinedatec-ci/pull/327). Source activation is PR #210; actual post-merge materialization remains required.

About and Release notes attach as AppKit modal sheets to the selected document window. About provides a Close button and Escape because sheet presentation does not expose standalone window controls. Close ends the sheet before startup continuation; menu presentation receives the document parent explicitly. Tracking: [#247](https://github.com/PinedaTec-EU/LeonardoMD/issues/247).
