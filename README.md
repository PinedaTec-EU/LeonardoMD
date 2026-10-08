# LeonardoMD

Native macOS Markdown reading and editing, backed by real local files. Open a single document for a clean, fast viewer, or open a folder as a project with navigation, search and optional Git.

## Run

Requires macOS 14 or later and Swift 6 / Xcode command-line tools.

```sh
./launch.sh
```

The entrypoint builds an optimized, locally signed app at `output/LeonardoMD.app` and opens it. A document path can be supplied as an argument. You can also open Markdown files with LeonardoMD from Finder's **Open With** menu. No account, API key or network connection is needed to read documents.

## Document and project modes

- **Standalone viewer:** open a `.md`, `.markdown` or `.txt` without creating a project or showing its folder. Global preferences apply. Choose **Open folder as project** when you want navigation.
- **Project:** open a folder, navigate its files, search names and content, and create, rename, move or delete items. Folders load children on expansion. Recent projects appear in the toolbar menu.
- **Workspace:** select or create a root folder, discover its projects, and create, rename or delete project folders from the workspace manager.
- **Recent items:** File provides separate document, project and workspace histories. Entries show their parent path; unavailable targets are disabled. Each submenu can clear its own history.
- **Focus:** hides project navigation and the inspector while preserving the document and project. Toggle it again to restore those panels.
- **Reading / Editing / Split:** native source editing with undo, autosave and an approximately synchronized rendered preview. External file changes reload clean documents; conflicting edits stay protected until you reload or save a copy.

| Shortcut | Action |
| --- | --- |
| ⌘O | Open document |
| ⇧⌘O | Open project |
| ⌘1 / ⌘2 / ⌘3 | Reading / Editing / Split |
| ⇧⌘F | Focus |
| ⌥⌘I | Document outline |
| ⌘S | Save |
| ⇧⌘E | Export PDF |

## Rendering and extensions

The preview supports CommonMark/GFM headings, lists, quotes, tables, tasks, highlighted code, relative images and links, and optional frontmatter metadata. Engines and fonts are bundled for offline use; library licenses are included alongside the renderer resources.

**Mermaid and mathematics are disabled by default.** Enable them in Extensions globally for the standalone viewer or override them for a project. Disabled engines are excluded from the WebKit resource allowlist and are neither loaded nor executed. Changing the active engines tears down the old execution context. Mermaid also renders visible diagrams lazily. Disabling an engine leaves its source readable.

PDF export uses the rendered document. Palettes and lightweight ruled/grid/parchment effects are configurable globally or per project. Project settings are portable JSON in `.leonardomd/project.json`; unknown schema versions are rejected. User preferences are stored separately in `~/Library/Application Support/LeonardoMD/preferences.json`.

Custom palette colors can be edited and imported/exported as JSON. The app validates reading contrast before applying them. Main-window and sheet controls share palette colors and tactile hover/pressed states.

## Document tags

Tags in YAML frontmatter appear as clickable pills above the preview, even when the metadata table is hidden. In a project, clicking a pill fills the sidebar search and reveals navigation if focus mode was active. Standalone documents show their tags without creating a project.

Use `tag:swift` or `tag:"Design Systems"` in project search. Matching is exact and ignores case; body mentions and partial tags do not match. Ordinary queries still search filenames and content. Tags accept a single string, an inline list (`tags: [Swift, "Design Systems"]`), or a block list under `tags:`. Empty tags are omitted and duplicates are collapsed ignoring case. Quoted strings support commas, spaces, escaped double quotes and doubled YAML apostrophes. This uses the existing lightweight metadata parser's string/list subset; nested tag mappings, YAML anchors, folded scalars and multiline flow lists are outside that subset.

## Optional Git

Enable Git tools in the project's preferences. The app can detect or initialize a repository, show changes and ahead/behind state, stage selected files, commit, view history and run manual fetch/pull/push. It uses `/usr/bin/git` and your existing system credentials. Pull uses fast-forward only, protects dirty worktrees and reports conflicts; it does not silently resolve them.

## Development

### Startup diagnostics

Startup emits JSON lines synchronously to stderr and at notice level to the macOS unified log under subsystem `eu.pinedatec.LeonardoMD`, category `startup`. Records include the phase, elapsed milliseconds, PID/parent PID, launch timestamp, bundle identifier/version/build, app-bundle status, OS and architecture. The activation-policy milestone records both the switch result and the actual policy (0 = regular, 1 = accessory, 2 = prohibited). Documents, full paths, command arguments and environment values are excluded. Missing bundle versions appear as `unknown`.

The `application_initializing` record is emitted before `NSApplication.shared`. If it is the last phase, inspect the crash stack and process-registration logs before blaming window or document code. Later milestones distinguish delegate setup, the event loop, menus, first-window construction and readiness. These breadcrumbs diagnose failures; they cannot recover from a framework abort. A stderr capture survives an abort even when the execution sandbox prevents unified-log delivery.

To inspect retained startup records, use Console with the subsystem/category above, or run:

```sh
/usr/bin/log show --last 15m --style compact --predicate 'subsystem == "eu.pinedatec.LeonardoMD" AND category == "startup"'
```

For GUI QA, use the packaged app through `./launch.sh` from a normal GUI terminal. A directly spawned AppKit executable inside an agent execution sandbox can abort during HIServices registration before creating a window. Compare the same binary outside that sandbox before changing product behavior. PID and launch timestamp distinguish diagnostic attempts from user sessions.

```sh
swift test
```

The package separates `LeonardoCore` (files/configuration/Git), `LeonardoRender` (WebKit and bundled engines) and `LeonardoApp` (macOS shell). The sample project in `Examples/Proyecto` exercises relative links, local images, diagrams, code, tables, metadata, tasks and mathematics.

Product stories are in [doc/US](doc/US). The two presentation modes and opt-in engine policy are specified in [US.000016](doc/US/us.000016.md) and [ADR 0001](doc/adr/0001-native-macos-and-lazy-extensions.md). Delivery is tracked by [issue #1](https://github.com/PinedaTec-EU/LeonardoMD/issues/1).

The generated app is signed locally for development. Public distribution, notarization and other platform UIs require their own release workflow.

The application icon uses the approved Leonardo Classic folded-L artwork. Its original PNG and multi-resolution macOS ICNS are stored in `assets/AppIcon`; the packaging script includes the ICNS in the signed bundle for Finder and the Dock.

## App updates

Distribution builds include Sparkle 2.9.6. Use **LeonardoMD → Check for updates…** (Spanish: **Buscar actualizaciones…**) to check and install an update. Enable **Automatically check for updates** (Spanish: **Comprobar actualizaciones automáticamente**) for periodic checks (off initially; Sparkle stores the preference globally). Installation remains user initiated. Sparkle displays release notes, errors and the no-update result and verifies Ed25519 signatures before extraction. Its quit request goes through the application's existing unsaved-document and Git-operation termination guard.

The stable feed is `https://github.com/PinedaTec-EU/LeonardoMD/releases/latest/download/appcast.xml`. Public downloads require no GitHub token. Development builds without `SPARKLE_PUBLIC_KEY` display an explanatory dialog and cannot enable periodic checks.

Beta candidates use a separate HTTPS feed and only opt into the beta Sparkle channel. Every channel displays the canonical numeric `release.feature.build` version without maturity suffixes; channel identity stays in updater/feed metadata. Update ordering uses the monotonic numeric build shared with stable releases.

See [signed release preparation](doc/releases.md). The channel becomes usable only after the first signed distribution release; an appcast alone is insufficient.
Extension controls live in **Preferences → Extensions**. Select Global or This project before changing Mermaid or mathematics; project inheritance restores the global settings. The document inspector contains heading navigation.

## Release versioning

The owner-approved baseline is **0.1.56**. Packaging requires Python 3 and derives bundle metadata from `version.nfo`. The `release.feature.build` model uses one `deploy/version/entries/<PR>.yaml` per source PR; successful Swift compilation commands accumulate its build delta; release notes use the verified source PR title after publication. See [the ledger workflow](doc/release-version-ledger.md) for operator use, trusted CI access and pending central automation activation.

Interface language defaults to English. Preferences → Language offers English and Español; see [localization](doc/localization.md) for resource maintenance.
