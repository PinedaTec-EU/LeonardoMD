# Interface languages

LeonardoMD defaults to **English**, independently of the macOS language. Choose
**English** or **Español** in Preferences → Language. This is a global interface
preference, stored as `interfaceLanguage` in the application's UserDefaults;
it is never written to a shared project. Changes update open SwiftUI surfaces
and the native application menus without recreating document sessions.

Application-owned strings live in
`Sources/LeonardoApp/Resources/Localization/en.json` and `es.json`. English
source text is the stable lookup key. `Localization.swift` loads the processed
SwiftPM resources once and provides English fallback for missing translations.
Keep user content, file paths, Git command output and technical diagnostics out
of translation catalogs. Operating-system dialogs and Sparkle's own UI use
those components' localization.

To add a language:

1. Add an ISO language-code case and native display name to `AppLanguage`.
2. Add `<code>.json` alongside the existing catalogs, with identical keys.
3. Preserve format placeholders (`%@`, `%d`, `%.1f`) in the same order.
4. Run `LocalizationTests`, then inspect preferences and document views.

Use `L10n.text` for labels and `L10n.format` for interpolated messages. Store
status keys or structured state rather than translated status strings so an
open view can translate them again after a language change. Accessibility
identifiers remain language independent.

`LocalizationVisualTests` optionally exports native host captures when
`LEONARDO_LOCALIZATION_EVIDENCE` names an output directory. The same hosting
views are retained while changing languages, exercising live observation.
The test uses empty sessions and does not launch the application's
single-instance process. Layer-backed native controls may be absent from
cache-display captures; use real application screenshots for those controls.

Tracking: [#57](https://github.com/PinedaTec-EU/LeonardoMD/issues/57).
