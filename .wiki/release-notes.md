# Native release notes

Central optional summaries and `changes_output_path` own generated change data;
Leonardo packages the byte-identical JSON and validates version/source arithmetic
at load. The native controller runs once per primary startup after Finder opens,
then continues default-app prompting after dismissal. The per-version suppression
switch defaults on; manual app-menu access bypasses automatic suppression.
Preferences preserve the interval for repeated notices and label unknown/earlier
version history. Tests cover offline identity/history rejection, preferences,
startup continuation/manual reopening and native en/es light/dark captures.
See [release contract](../doc/release-version-ledger.md#native-release-notes).
Tracking: [#209](https://github.com/PinedaTec-EU/LeonardoMD/issues/209).
