# LeonardoMD

Native macOS Markdown reading and editing, backed by real local files. Open a single document for a clean, fast viewer, or open a folder as a project with navigation, search and optional Git.

## Run

Requires macOS 14 or later and Swift 6 / Xcode command-line tools.

```sh
./launch.sh
```

The entrypoint builds an optimized, locally signed app at `output/LeonardoMD.app` and opens it. A document path can be supplied as an argument. You can also open Markdown files with LeonardoMD from Finder's **Open With** menu. On startup, distribution builds offer to become the default for `.md` and `.markdown` if needed: choose **Use LeonardoMD**, **Ask next time**, or **Never ask again**. **Preferences → General → Default Markdown application** shows the current status and lets you change the default or re-enable the prompt. This setting applies to the whole Mac, including every project; `.txt` and individual file overrides are unaffected. macOS may ask for consent, and cancellation or failure is reported without claiming success. No account, API key or network connection is needed to read documents.

## Document and project modes

- **Standalone viewer:** open a `.md`, `.markdown` or `.txt` without creating a project or showing its folder. Global preferences apply. Choose **Open folder as project** when you want navigation.
- **Project:** open a folder, navigate its files, search names and content, and create, rename, move or delete items. Folders load children on expansion. Recent projects appear in the toolbar menu.
- **Workspace:** select or create a root folder, discover its projects, and create, rename or delete project folders from the workspace manager.
- **Recent items:** File provides separate document, project and workspace histories. Entries show their parent path; unavailable targets are disabled. Each submenu can clear its own history.
- **Focus:** hides project navigation and the inspector while preserving the document and project. Toggle it again to restore those panels.
- **Reading / Editing / Split:** protected-by-default source and rendered-text editing, native undo and an approximately synchronized preview. Unlock the toolbar padlock to edit; use Save or ⌘S to persist changes. Unsaved drafts are marked explicitly and closing or navigating away offers Save, Discard or Cancel. Preview editing preserves untouched Markdown; raw HTML, rendered math and diagrams are edited through the raw Edit view. External file changes reload clean documents; conflicting edits stay protected until you reload or save a copy.

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

## Open Leonardo documents and forms

Leonardo documents use `.mdlf`, an open UTF-8 Markdown body with versioned JSON metadata for fields, answers and layout. Standard `.md` files retain normal Markdown behavior. **Preferences → General** can opt into saving Markdown edits as MDLF while preserving the original file. A file carrying an explicit Leonardo declaration with a Markdown extension shows a conversion notice.

Export a form as `.mdlr` to open it in **Fill form** mode. Fill the declared fields in the inspector; validation messages do not prevent saving an unfinished draft. Structural source editing remains available through the document mode and protection controls. Background images, image dimensions/placement and table column widths are declared in the public metadata contract.

**Export Leonardo package** produces an ordinary `.mdlz` ZIP containing one MDLF/MDLR document and its local resources under `assets/`. Package opening defaults to editing the package itself; preferences can ask or extract to a new folder. When working in an extracted folder, Save updates those ordinary files and **Export Leonardo package** creates a new transport package. The title and status bar distinguish format, storage and mode so the save destination stays visible.

See the [format specification, schema and examples](doc/format/README.md) and the [Codex/Claude plugin and MDLZ generation guide](doc/plugins/leonardo-format.md). No proprietary binary document representation is required.

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

Distribution builds include Sparkle 2.9.6. Open **LeonardoMD → Preferences… → Updates** (Spanish: **Preferencias… → Actualizaciones**) to select **Stable** or **Beta**, check now, or enable periodic checks. Stable is initially selected even for an installed beta package; beta participation requires an explicit user choice. The choice applies to every window on this Mac, independently of project scope, and survives package updates. Sparkle persists automatic checking (initially off) and the last check date. Installation remains user initiated; automatic installation is disabled.

Preferences show the installed numeric version and its package channel separately from the selected subscription. Beta includes newer stable releases as well as beta candidates. Returning to stable never downgrades: the installed beta remains until a newer stable build is published. Finish or cancel an active update before changing channel. Sparkle displays release notes, errors and the no-update result and verifies Ed25519 signatures before extraction. Its quit request goes through the application's existing unsaved-document and Git-operation termination guard.

The stable feed is `https://github.com/PinedaTec-EU/LeonardoMD/releases/latest/download/appcast.xml`. The beta subscription feed is `https://raw.githubusercontent.com/PinedaTec-EU/LeonardoMD/update-feeds/beta/appcast.xml` and must contain both stable and beta entries. Public downloads require no GitHub token. Development builds without a configured matching `SPARKLE_PUBLIC_KEY` explain why checks are unavailable in Preferences.

Both newly packaged channels use the existing stable update signing key. Old beta packages signed with a different key require manual installation of a new signed, notarized distribution; changing their feed alone cannot migrate their trust root. Every channel displays the canonical numeric `release.feature.build` version without maturity suffixes; channel identity stays in updater/feed metadata. Update ordering uses the monotonic numeric build shared with stable releases.

See [signed release preparation](doc/releases.md). The channel becomes usable only after the first signed distribution release; an appcast alone is insufficient.
Extension controls live in **Preferences → Extensions**. Select Global or This project before changing Mermaid or mathematics; project inheritance restores the global settings. The document inspector contains heading navigation.

Drag the divider beside the project files/folders sidebar to widen or narrow it. The native split view keeps navigation and document panes usable.

## Release versioning

The owner-approved baseline is **0.1.56**. Packaging requires Python 3 and derives bundle metadata from `version.nfo`. The `release.feature.build` model uses one `deploy/version/entries/<PR>.yaml` per source PR; successful Swift compilation commands accumulate its build delta; release notes use the verified source PR title after publication. See [the ledger workflow](doc/release-version-ledger.md) for operator use, trusted CI access and pending central automation activation.

Interface language defaults to English. Preferences → General → Language offers English and Español; see [localization](doc/localization.md) for resource maintenance.

### Native QA launches

Use `./launch.sh --qa` to build and launch a disposable copy of the real app. The helper preserves the executable, resources and frameworks, gives the copy a unique bundle identity and re-signs it. Packaging rejects an incorrect executable or a direct XCTest dependency before launch. Run XCTest checks with `swift test`; never package `xctest` as a GUI app.

The command prints the temporary bundle path. Existing LeonardoMD instances keep product-wide single-instance ownership; a forwarded launch does not verify fresh startup. Confirm a new PID and `application_ready` startup records before claiming a fresh-process pass. Quit your existing app normally first when you want a separate startup check. Remove the printed temporary directory only after its QA process has finished.

For preparation without launch, run `python3 scripts/qa-bundle.py output/LeonardoMD.app` after packaging. Tracking: [issue #80](https://github.com/PinedaTec-EU/LeonardoMD/issues/80).

## Markdown table widths

An optional standalone comment immediately before a GFM table sets its column
widths without changing standard Markdown table syntax:

```markdown
<!-- leonardo:table widths="10ch 15ch auto" -->

| Fecha | Prueba | Resultado esencial |
| :--- | :--- | :--- |
| 14/10/2026 | Analítica | Sin alteraciones |
```

Use one value per column: an integer from `1ch` to `200ch`, or `auto`. `ch` is
approximately the width of the font's zero character, not a count of arbitrary
letters; the specified width is for content, with cell padding added. `auto`
columns share remaining space, with a readable minimum of 12ch each. Without
`auto`, the table keeps the specified widths rather than stretching to fill the
preview. Narrow viewports scroll horizontally. Headers wrap onto multiple lines;
unbroken tokens wrap only when necessary inside explicitly sized columns.

Blank lines are allowed between the comment and table, but intervening content
ends its scope. It applies only once, including inside a list or block quote.
Invalid directives or a column-count mismatch are ignored; fenced code examples
are never interpreted. Other Markdown viewers ignore the comment and render the
ordinary table. Tables without a directive use natural widths and preserve whole
words, scrolling horizontally when necessary.
