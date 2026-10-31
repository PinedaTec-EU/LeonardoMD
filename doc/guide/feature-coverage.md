# User-help feature coverage

Source audit: 31 October 2026. This maps the implemented macOS surfaces to the
same numbered chapters in `en/body.md` and `es/body.md`. It is a maintenance map,
not a promise that every feature is in the current stable distribution. Check
release notes for the installed build. Future feature PRs maintain this map and
both locales under `.skills/leonardo-user-guide/SKILL.md`.

| Capability / behavior checked | Implementation reference | Chapters | Illustration / exercise |
| --- | --- | --- | --- |
| Personal guide copy; Help/Welcome; language; preserve saved answers across revisions | `BundledUserGuide.swift`, `DocumentTabs.swift`, `LeonardoMD.swift` | Introduction, 4 | Header, live practice fields, Home capture |
| Supported standalone files vs project folders; protection; save decisions | `AppSession.swift`, `WorkspaceView.swift`, `ProjectSidebar.swift` | 1–2, 8, 10 | Document journey diagram |
| MDLF/MDLR metadata, field definitions/values and inline fill/help | `../LeonardoCore/LeonardoFormatTypes.swift`, `SessionLeonardoFields.swift`, `DocumentInspector.swift` | 2–4 | Minimal valid source, practice form |
| Markdown migration keeps original; package vs extracted-folder saving | `LeonardoFormatPreferences.swift`, `SessionLeonardo.swift` | 3, 5 | Package contents diagram |
| Package, response, Markdown and PDF export; loss/remote resource limits | `SessionMarkdownExport.swift`, `SessionLeonardoExport.swift`, `../LeonardoRender/MarkdownPDFExportCoordinator.swift` | 5, 10, 18–19 | Export decision diagram |
| External agent skill installation vs runtime app control; attachment limitations | `plugins/leonardo-format/skills/leonardo-format/SKILL.md`, `doc/plugins/leonardo-format.md` | 6 | Copyable prompts; provider instructions retain their explicit check date |
| Recents, favorites, project theme association and unavailable paths | `SavedItemsView.swift` | 7 | Home capture (empty initial state) |
| Tree, CRUD, tab identity, filters, sort, follow-active and Focus | `ProjectSidebar.swift`, `DocumentTabs.swift`, `SessionPreferences.swift` | 8 | Stepwise instructions; keyboard table |
| Filename/content search, exact tag filter and heading outline | `ProjectSidebar.swift`, `DocumentInspector.swift`, `../LeonardoCore/FrontMatterTags.swift` | 9 | YAML and search examples |
| Source/preview/split editing, shared undo, table widths, file conflict recovery | `MarkdownEditor.swift`, `SessionTableResizing.swift`, `SessionConflictCopy.swift`, `WorkspaceView.swift` | 10 | Recovery choices explained; source examples |
| Global/project/Mac scope, palettes/contrast, associations, instances | `PreferencesView.swift`, `PaletteEditor.swift`, `MarkdownAssociationPreferences.swift`, `InstancePreferencesView.swift` | 11 | Palette capture, scope table |
| All five opt-in engines, actual Mermaid/KaTeX/Vega examples and citation/extras syntax | `ExtensionPreferences.swift`, `../LeonardoRender/Resources/` | Live demonstrations, 12 | Three live outputs; literal citation/footnote/callout examples |
| Own-extension detection, grouped consent, global/project scope, suppression/reset | `ExtensionRecommendations.swift`, `ExtensionRecommendationPresenter.swift` | Live demonstrations, 12 | Original activation and reset captures |
| Manual Git init/status/stage/commit/history/fetch/pull/push; ff-only and credentials | `GitPanel.swift`, `../LeonardoCore/GitRepository.swift` | 13 | Ordered local-to-remote workflow |
| Read-only Little Leonardo, explicit sharing, QR/code verification, address/VPN and revocation | `MobileSyncPreferencesView.swift`, `DesktopSyncController.swift` | 14 | Disabled-service initial-state capture |
| Linked Macs, imports/offline edits, comparison/proposals and source review | `DesktopPeerPreferencesView.swift`, `DesktopPeerController.swift` | 15 | Empty linked-Macs capture; proposal steps |
| Stable/beta subscription vs installed channel, checks/install guards, release notes | `ApplicationUpdates.swift`, `UpdatePreferencesView.swift`, `LeonardoMD.swift` | 16 | Stable subscription capture with fake updater |
| Menu shortcuts including Fill form; limits/network/privacy/recovery | `LeonardoMD.swift`, `doc/releases.md` | 17–19 | Shortcut table, problem/action list |

Source paths above are relative to `Sources/LeonardoApp/` except explicit target
or documentation prefixes. Screenshots illustrate actual production components
using isolated synthetic data, not device connectivity or updater acceptance.
Their original capture contexts/metadata live beside the PNGs in each locale's
`assets/`; only PNG content assets enter MDLZ. Diagrams are generated illustrations.

## Availability boundaries retained

- Field formulas/calculated values are deferred in [#203](https://github.com/PinedaTec-EU/LeonardoMD/issues/203); a KaTeX equation is presentation only.
- Windows availability must not be inferred from desktop architecture; [#227](https://github.com/PinedaTec-EU/LeonardoMD/issues/227) remains separate.
- The iOS companion is read-only; desktop incoming proposals do not imply mobile editing.
- The bundled help's inline filling instructions supersede the obsolete web-manual inspector instruction tracked in [#225](https://github.com/PinedaTec-EU/LeonardoMD/issues/225). That issue remains separately scoped until the owner includes the web manual.
- The updater Preferences-sheet workaround stays explicit under [#202](https://github.com/PinedaTec-EU/LeonardoMD/issues/202); screenshots do not prove every channel/install transition.
