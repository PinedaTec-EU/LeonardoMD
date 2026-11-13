# User-help feature coverage

Source audit: 12 November 2026. This maps implemented macOS and Little Leonardo
surfaces to the same numbered chapters in `en/body.md` and `es/body.md`. It is a maintenance map,
not a promise that every feature is in the current stable distribution. Check
release notes for the installed build. Future feature PRs maintain this map and
both locales under `.skills/leonardo-user-guide/SKILL.md`.

| Capability / behavior checked | Implementation reference | Chapters | Illustration / exercise |
| --- | --- | --- | --- |
| Personal guide copy; Help/Welcome; language; separate practice copy; preserve saved answers across revisions | `BundledUserGuide.swift`, `DocumentTabs.swift`, `LeonardoMD.swift` | Introduction, 4 | Header, separate practice form, Home capture |
| Supported standalone files vs project folders; protection; save decisions | `AppSession.swift`, `WorkspaceView.swift`, `ProjectSidebar.swift` | 1–2, 8, 10 | Document journey diagram |
| Persistent active-file selection independent of automatic following; appearance-aware Leonardo filename colors | `FileTreeRow.swift`, `FileListMenu.swift` | 11 | Text explanation; opt-in native light/dark row captures in `SidebarSelectionTests` |
| MDLF/MDLR metadata, field definitions/values and inline fill/help | `../LeonardoCore/LeonardoFormatTypes.swift`, `SessionLeonardoFields.swift`, `DocumentInspector.swift` | 2–4 | Minimal valid source, separate practice form |
| Markdown migration keeps original; package vs extracted-folder saving | `LeonardoFormatPreferences.swift`, `SessionLeonardo.swift` | 3, 5 | Package contents diagram |
| Package, response, Markdown and PDF export; loss/remote resource limits | `SessionMarkdownExport.swift`, `SessionLeonardoExport.swift`, `../LeonardoRender/MarkdownPDFExportCoordinator.swift` | 5, 10, 18–19 | Export decision diagram |
| External agent skill installation vs runtime app control; attachment limitations | `plugins/leonardo-format/skills/leonardo-format/SKILL.md`, `doc/plugins/leonardo-format.md` | 6 | Copyable prompts; provider instructions retain their explicit check date |
| File → Import with your agent opens a localized standalone Leonardo guide; PDF conversion is performed by the user’s external agent | `BundledUserGuide.swift`, `LeonardoMD.swift`, `scripts/package-user-guide.py` | 6 | Shared bilingual chapter; premium illustrative PDF → agent/skill → editable document image and copyable request |
| Recents, favorites, project theme association and unavailable paths | `SavedItemsView.swift` | 7 | Home capture (empty initial state) |
| Tree, CRUD, tab identity, filters, sort, follow-active and Focus | `ProjectSidebar.swift`, `DocumentTabs.swift`, `SessionPreferences.swift` | 8 | Stepwise instructions; keyboard table |
| Project filename/content search, document-source search across current/all open tabs, literal and regex matching, exact tag filter and heading outline | `ProjectSidebar.swift`, `DocumentSearch.swift`, `DocumentTabsSearch.swift`, `DocumentInspector.swift`, `../LeonardoCore/FrontMatterTags.swift` | 9, 17 | YAML, search modes/scopes and keyboard shortcuts |
| Source/preview/split editing, shared undo, table widths, file conflict recovery | `MarkdownEditor.swift`, `SessionTableResizing.swift`, `SessionConflictCopy.swift`, `WorkspaceView.swift` | 10 | Recovery choices explained; source examples |
| Global/project/Mac scope, palettes/contrast, associations, instances | `PreferencesView.swift`, `PaletteEditor.swift`, `MarkdownAssociationPreferences.swift`, `InstancePreferencesView.swift` | 11 | Palette capture, scope table |
| All five opt-in engines, actual Mermaid/KaTeX/Vega examples and citation/extras syntax | `ExtensionPreferences.swift`, `../LeonardoRender/Resources/` | Live demonstrations, 12 | Three live outputs; literal citation/footnote/callout examples |
| Own-extension detection, grouped selection, per-extension activation, global warning suppression/reset, legacy suppression cleanup | `BuiltInExtension.swift`, `ExtensionRecommendations.swift`, `ExtensionRecommendationPresenter.swift` | Live demonstrations, 12 | Bilingual multi-extension selection and reset captures; reset never changes activation preferences |
| Manual Git init/status/stage/commit/history/fetch/pull/push; ff-only and credentials | `GitPanel.swift`, `../LeonardoCore/GitRepository.swift` | 13 | Ordered local-to-remote workflow |
| Synchronization → Share from this Mac: common service, saved content for read-only Little Leonardo and desktop clients, invitation/code verification, address/VPN, grants/revocation, incoming review and targeted rubric capture | `SynchronizationPreferencesView.swift`, `MobileSyncPreferencesView.swift`, `SyncDeviceRole.swift`, `DesktopSyncController.swift`, `RubricCaptureStore.swift`, `RubricEditor.swift` | 14 | `sync-sharing-v14.png` and `sync-review-draft-unavailable.png` in both locales, plus linked rubric request/review and automatic-recovery/persistent-error captures; synthetic disabled-service, retained-device and gated-action states |
| Project identity and role direction: local Demo, shared from this device, received from another device, recovery archive and independent on-demand file states | `../LeonardoCore/ProjectIdentity.swift`, `ProjectSidebar.swift`, `SavedItemsView.swift`, `MobileLibraryView.swift`, `DesktopPeerPreferencesView.swift` | 14–15 | `project-identities.png` plus bilingual source/recipient example; role indicator is separate from connectivity and selected-content scope |
| Little Leonardo iOS rubric capture: linked-device request consent, Classic palette, startup/About, rotation-aware full-screen finger/Pencil drawing, manual expansion, undo/clear/preview, durable unsent draft restore, frozen bounded response and explicit send/retry | `Mobile/LittleLeonardo/MobileLibrary.swift`, `Mobile/LittleLeonardo/MobileRubricCaptureView.swift`, `LeonardoSync/MobileRubricDraft.swift` | 14 | Spanish simulator capture and native HTTPS fixture; capture-only, no document grant or physical-device/TestFlight claim |
| Little Leonardo interrupted HTTPS diagnostics: operation, HTTP status, received/expected bytes and system domain/code | `Mobile/LittleLeonardo/MobileLibrary.swift`, `Sources/LeonardoSyncTransport/PinnedHTTPSClient.swift`, `Sources/LeonardoSyncTransport/HTTPSFailureDiagnostics.swift` | 14 | Safe `[LL1 ...]` explanation in both locales; native sync failure capture and real TLS cutoff test; no URL, credential, identifiers or response content |
| Synchronization → Connect to other computers: independent client role, connections, imports/offline edits, comparison/proposals and intervals | `SynchronizationPreferencesView.swift`, `DesktopPeerPreferencesView.swift`, `DesktopPeerController.swift` | 15 | `sync-connections-v14.png` in both locales; empty connections/copies and disabled Connect; proposal steps |
| Stable/beta subscription vs installed channel, checks/install guards, release notes | `ApplicationUpdates.swift`, `UpdatePreferencesView.swift`, `LeonardoMD.swift` | 16 | Stable subscription capture with fake updater |
| Menu shortcuts including Fill form; limits/network/privacy/recovery | `LeonardoMD.swift`, `doc/releases.md` | 17–19 | Shortcut table, problem/action list |

Source paths above are relative to `Sources/LeonardoApp/` except explicit target
or documentation prefixes. Screenshots illustrate actual production components
using isolated synthetic data, not device connectivity or updater acceptance.
Their original capture contexts/metadata live beside the PNGs in each locale's
`assets/`; only PNG content assets enter MDLZ. The four explanatory diagrams are premium generated PNG illustrations (1200×400); live Mermaid examples remain editable demonstrations.

## Availability boundaries retained

- Field formulas/calculated values are deferred in [#203](https://github.com/PinedaTec-EU/LeonardoMD/issues/203); a KaTeX equation is presentation only.
- Windows availability must not be inferred from desktop architecture; [#227](https://github.com/PinedaTec-EU/LeonardoMD/issues/227) remains separate.
- The iOS companion is read-only; desktop incoming proposals do not imply mobile editing.
- The bundled help's inline filling instructions supersede the obsolete web-manual inspector instruction tracked in [#225](https://github.com/PinedaTec-EU/LeonardoMD/issues/225). The web manuals are generated from the same canonical bilingual editorial sources.
- The updater Preferences-sheet workaround stays explicit under [#202](https://github.com/PinedaTec-EU/LeonardoMD/issues/202); screenshots do not prove every channel/install transition.

Practice navigation ([#312](https://github.com/PinedaTec-EU/LeonardoMD/issues/312)):
`GuidePracticeNavigation.swift` binds the fixed localized resource destination to
the live guide/session/source and active tab. Since Guide v6, the guide is read-only content;
practice v1 is a separate MDLR. Reopening selects the existing practice tab in
Fill mode. Cmd-4 fills, the padlock edits structure, and Cmd-S saves answers.

Page objects/rubrics (#193): `DocumentToolbar.swift`, `SessionGraphics.swift`, `RubricEditor.swift`, `RubricLibrary.swift`, `RubricCaptureStore.swift`, `LeonardoGraphic.swift`, `leonardo-objects.js`, `MarkdownPagePDF.swift`; chapters 4, 5, 10, 14. Covers geometry/Z, menu drawing, local library, protected fields, targeted helper-owned rubric capture, explicit review/save, overflow and Markdown/PDF limits. Follow-up #323/#322 adds `GraphicInspector.swift`/`SessionGraphicInspection.swift`, read-only floating summary, copied-ink color, reliable deselection and v8 inspector illustrations. The iOS capture path is a separate read-only response channel: it grants no document access and only publishes a bounded rubric after explicit send.

Sync helper (#319): chapters 14–15 cover per-user installation/approval, the required master switch in both directions, saved-file snapshots, offline status with the editor open, after-login recovery, editor-independent sharing and manual incoming review. Current Guide v20 retains these helper instructions in a separate personal copy.

Synchronization roles (#337): chapters 14–15 now route through one Synchronization category, one service control and separate sharing/consuming pages. Refreshed EN/ES production-component images show both pages with isolated disabled settings; capability labels and invite QR/link equivalence are explained. Guide v20 opens a new personal copy; existing older guide copies and separate practice answers are preserved.

Remote project review (#429), ignored-grant reconciliation (#432), stable helper status (#421), and offline catalogue restoration (#436): chapters 14–15 explain host naming, explicit project acceptance, ignored projects remaining dismissed until the host removes or changes scope/selection, new-file notices, on-demand open/retention, preserved pre-review projects, stable status through helper checks, persistent failure diagnostics, manual linked-device refresh, and browsing the last saved catalogue for accepted projects after an offline restart. macOS keeps its source-host controls; Little Leonardo groups connections by host and expands accepted projects into files with per-project/file menus. Local acceptance remains separate from host authorization. Guide v72 assigns these contents a distinct personal-copy revision so existing Guide v68 copies cannot hide the corrected help; earlier guide copies and practice answers remain untouched.
Update termination (#202): chapter 16 documents automatic Preferences dismissal before install approval, retained Save/Git decisions, cancellation/retry, and the older-source bootstrap workaround. Introduced in Guide v12 and retained in current Guide v23; previous personal copies are preserved.

Display-math regression coverage ([#272](https://github.com/PinedaTec-EU/LeonardoMD/issues/272)): both guides include one-line underbraces and a multiline tagged box-counting equation. Native help QA must inspect enabled rendering and disabled/code fallback in every tested instance.

| Metadata-first browsing, navigable folder hierarchy, retention and cache management | `DownloadLibrary`, `OnDemandCache`, `LeonardoSyncUI` | 15 | Bilingual storage table; immediate-child folder navigation; explicit draft/apply budget; remote/cached/offline states; editable-copy boundary |
| Host attribution, review of new projects/files, stable status and quieter linked-device refresh | `DesktopPeerRemoteProjectsView`, `DesktopPeerReviewStore`, `MobileSyncPreferencesView`, `MobileSharedProjectTreeView`, `MobileDirectConnectionStore` | 14–15 | Mac host preferences; Little Leonardo host → project → file disclosure; add/ignore decisions; ellipsis actions; transfer progress/failure; swipe removal from this device; on-demand open vs offline retention and local space release; preserved existing projects; manual device refresh |

Extensible Math and outline navigation ([#274](https://github.com/PinedaTec-EU/LeonardoMD/issues/274), [#364](https://github.com/PinedaTec-EU/LeonardoMD/issues/364)): live braces, radical, long arrow and cancellation marks; chapter 9 explains repeated titles and Split navigation. Native tests verify geometry, active-content rejection, original source-line identity and preview/editor feedback.

Little Leonardo offline demo (#381) and HTTPS failure diagnostics (#380): `MobileDemoStore.swift`, `MobileDemoView.swift`, bundled `Demo/`, and the privacy-safe `[LL1 …]` transfer example; bilingual mobile appendix, first-run copies, local-only practice/save/reset/source, read-only sync boundary, and guidance to report the bounded code. Guide v23 preserves personal copies through v22. Fresh native acceptance and original demo captures: `doc/validation/little-demo/integrated-fixes/`; diagnostic evidence: `doc/validation/little-leonardo/`.

PR #398: Guide29 EN/ES documents same-request automatic status recovery, persistent error/Retry, terminal requests and close-versus-cancel behavior. Existing personal guides/practice answers remain preserved in prior revision directories. New illustrations are original production-component captures with synthetic data; they do not claim packaged/physical acceptance.

- Mobile project library: one ordinary Demo project with language documents; swipe + tap removal, persistent local exclusion and Settings recovery. Sources: `MobileProjectLifecycle.swift`, `MobileLibraryView.swift`; both guide bodies, Little Leonardo demo chapter.

Little Leonardo compact synchronized reader (#397): the first heading starts with a 16-point content margin in the iOS reader only; later section margins and the default desktop preview remain unchanged. Chapter 14 explains Preview/Source in both languages. Real iOS renderer and synchronized-document component captures are retained in `doc/validation/reader-spacing/`. Guide v31 preserves existing guide/practice copies.

Automatic helper renewal (#412): `SyncHelperBuildIdentity.swift`,
`SyncHelperController.swift` and `ConfigurationStore+HelperUpgrade.swift`; chapters
10 and14 now explain automatic renewal after an app update, temporary offline
state, explicit disable, interrupted renewal and macOS approval. Guide40 keeps
earlier personal copies separate. Fresh packaged ES/EN acceptance and production
preference components: `doc/validation/helper-upgrade/`. Signed installed automatic
replacement remains a post-publication check, distinct from the owner-confirmed
manual1215 recovery.

- #412 signed-update service preparation: chapter 14 in both locales explains the pre-install drain, preserved consent/access, cancellation, safe-install veto and the legacy migration limitation. Guide51; signed installed A→B acceptance remains pending by owner instruction.

PR #428 EN/ES retain the current search/help content and clarify that helper
checks keep the last confirmed indicator without a temporary gray state or “Sync
helper running” line, and explain how peer actions are gated while a source
review stays open across an outage. The `sync-review-draft-unavailable.png`
image is a synthetic native component capture in both locales and replaces the
older, narrower gated-action image to stay within the bundled image memory
budget. Existing personal guide copies and their practice answers remain
untouched. Current sources, package revision and build instructions are tracked
in [README.md](README.md).
