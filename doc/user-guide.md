# User guide

See the [README](../README.md) for installation and the product overview.

## Opening files and default application

Open documents from the app or Finder’s **Open With** menu. Distribution builds can offer to become the default for `.md` and `.markdown`. Choose **Use LeonardoMD**, **Ask next time** or **Never ask again**. **Preferences → General → Default Markdown application** shows the current status and lets you change it or re-enable the prompt. This Mac-wide setting does not change `.txt` or individual file overrides; macOS may request consent.

## Document and project modes

- **Standalone viewer:** open a `.md`, `.markdown` or `.txt` without creating a project or showing its folder. Global preferences apply. Choose **Open folder as project** when you want navigation.
- **Project:** open a folder, navigate its files, search names and content, and create, rename, move or delete items. Folders load children on expansion. Recent projects appear in the toolbar menu.
- **Workspace:** select or create a root folder, discover its projects, and create, rename or delete project folders from the workspace manager.
- **Recent items:** File provides separate document, project and workspace histories. Entries show their parent path; unavailable targets are disabled. Each submenu can clear its own history.
- **Focus:** hides project navigation and the inspector while preserving the document and project. Toggle it again to restore those panels.
- **Reading / Editing / Split:** protected-by-default source and rendered-text editing, shared document undo and an approximately synchronized preview. Unlock the toolbar padlock to edit; use Save or ⌘S to persist changes. Unsaved drafts are marked explicitly and closing or navigating away offers Save, Discard or Cancel. Preview editing preserves untouched Markdown; raw HTML, rendered math and diagrams are edited through the raw Edit view. External file changes reload clean documents; conflicting edits stay protected until you reload or save a copy.

| Shortcut | Action |
| --- | --- |
| ⌘O | Open document |
| ⇧⌘O | Open project |
| ⌘1 / ⌘2 / ⌘3 | Reading / Editing / Split |
| ⇧⌘F | Focus |
| ⌥⌘I | Document outline |
| ⌘S | Save |
| ⌘Z / ⇧⌘Z | Undo / Redo document edits |
| ⇧⌘E | Export PDF |

## Rendering and extensions

The preview supports CommonMark/GFM headings, lists, quotes, tables, tasks, highlighted code, relative images and links, and optional frontmatter metadata. Engines and fonts are bundled for offline use; library licenses are included alongside the renderer resources.

**Mermaid and mathematics are disabled by default.** Enable them in Extensions globally for the standalone viewer or override them for a project. Disabled engines are excluded from the WebKit resource allowlist and are neither loaded nor executed. Changing the active engines tears down the old execution context. Mermaid also renders visible diagrams lazily. Disabling an engine leaves its source readable.

Preferences keep their tab navigation fixed. General and Extensions each contain their own Global / This project selector. In General, palette and paper effect follow that scope; language, viewing behavior and Markdown file association are grouped separately as Mac-wide settings.

PDF export uses the rendered document. Palettes and lightweight ruled/grid/parchment effects are configurable globally or per project. Project settings are portable JSON in `.leonardomd/project.json`; unknown schema versions are rejected. User preferences are stored separately in `~/Library/Application Support/LeonardoMD/preferences.json`.

Custom palette colors can be edited and imported/exported as JSON. The app validates reading contrast before applying them. Main-window and sheet controls share palette colors and tactile hover/pressed states.

## Open Leonardo documents and forms

These workflows are currently available in beta releases, ahead of stable. Choose a release whose notes include Leonardo document support; the [stable download](https://github.com/PinedaTec-EU/LeonardoMD/releases/latest) follows GitHub's stable channel, not the newest beta.

Leonardo documents use `.mdlf`, an open UTF-8 Markdown body with versioned JSON metadata for fields, answers and layout. Standard `.md` files retain normal Markdown behavior. **Preferences → General** can opt into saving Markdown edits as MDLF while preserving the original file. A file carrying an explicit Leonardo declaration with a Markdown extension shows a conversion notice.

Export a form as `.mdlr` to open it in **Fill form** mode. Fill the declared fields in the inspector; validation messages do not prevent saving an unfinished draft. Structural source editing remains available through the document mode and protection controls. Background images, image dimensions/placement and table column widths are declared in the public metadata contract.

**Export Leonardo package** produces an ordinary `.mdlz` ZIP containing one MDLF/MDLR document and its local resources under `assets/`. Package opening defaults to editing the package itself; preferences can ask or extract to a new folder. When working in an extracted folder, Save updates those ordinary files and **Export Leonardo package** creates a new transport package. The title and status bar distinguish format, storage and mode so the save destination stays visible.

See the [format specification, schema and examples](format/README.md) and the [Codex/Claude plugin and MDLZ generation guide](plugins/leonardo-format.md). No proprietary binary document representation is required.

## Undo and Redo

Use **Undo** and **Redo** beside Save, or **Edit → Undo / Redo** (⌘Z / ⇧⌘Z), to restore source, preview and form edits. Each document session keeps its own history of up to 200 changes. Source edits require the padlock to be unlocked; form edits can be restored in Fill mode while the source remains protected. A new edit clears Redo.

Ordinary saves preserve history. Undoing a saved edit changes the draft without changing the file until you save again. Loading, reloading, discarding changes, converting formats or closing the session clears history. In particular, saving with automatic Markdown-to-MDLF migration starts a new history for the converted document. Search and other native text controls keep their own text undo when focused.

## Document tags

Tags in YAML frontmatter appear as clickable pills above the preview, even when the metadata table is hidden. In a project, clicking a pill fills the sidebar search and reveals navigation if focus mode was active. Standalone documents show their tags without creating a project.

Use `tag:swift` or `tag:"Design Systems"` in project search. Matching is exact and ignores case; body mentions and partial tags do not match. Ordinary queries still search filenames and content. Tags accept a single string, an inline list (`tags: [Swift, "Design Systems"]`), or a block list under `tags:`. Empty tags are omitted and duplicates are collapsed ignoring case. Quoted strings support commas, spaces, escaped double quotes and doubled YAML apostrophes. This uses the existing lightweight metadata parser's string/list subset; nested tag mappings, YAML anchors, folded scalars and multiline flow lists are outside that subset.

## Optional Git

Enable Git tools in the project's preferences. The app can detect or initialize a repository, show changes and ahead/behind state, stage selected files, commit, view history and run manual fetch/pull/push. It uses `/usr/bin/git` and your existing system credentials. Pull uses fast-forward only, protects dirty worktrees and reports conflicts; it does not silently resolve them.

## Preferences and language

Interface language defaults to English. **Preferences → General → On this Mac → Language** offers English and Español. Language and Markdown file association apply to the whole Mac. Palette and extension settings can apply globally or to the current project.

The document inspector contains heading navigation. Drag the divider beside the project sidebar to change its width.

The sidebar filter button opens file visibility and sorting controls. **Show all files** starts off; the default list contains folders and supported Markdown, text and Leonardo documents. **Show hidden files** remains independent. The **Sort** submenu offers **Folders first** (initially on) and **A–Z** or **Z–A**, including expanded subfolders. These controls belong to the current document session. Leonardo filenames and icons use wine coloring by default; General → Appearance can disable it globally or override it per project, with an option to inherit global file colors. Markdown colors stay unchanged.

## Updates

Open **LeonardoMD → Preferences… → Updates** (Spanish: **Preferencias… → Actualizaciones**) to choose Stable or Beta, check now or enable periodic checks. Stable is selected initially, including in beta packages. Automatic checking is initially off; installation requires user action.

The maintainer confirms that updates are detected and install successfully. A remaining [Preferences-sheet termination issue (#202)](https://github.com/PinedaTec-EU/LeonardoMD/issues/202) can leave the old instance running after Install and Relaunch. Save your work, close Preferences, and quit normally so the pending update can complete. This confirmation does not establish every channel transition or quit-cancellation acceptance scenario.

The installed package channel and the selected update subscription are separate. Beta subscriptions include newer stable releases. Switching to Stable never downgrades an installed beta: it waits for a newer stable build. Finish or cancel an active update before changing channel. Unsaved-document and Git-operation guards apply when an update requests termination.

Legacy beta packages signed with the former beta update key require manual installation of a current signed, notarized package; changing the feed cannot migrate their trust root. Development builds without a configured matching Sparkle key explain why checks are unavailable.

Published packages and notes are available in [GitHub Releases](https://github.com/PinedaTec-EU/LeonardoMD/releases). The [distribution contract](releases.md) records signing, feeds and remaining hosted updater acceptance scenarios.

## Table widths

See [Markdown table widths](table-widths.md) for the optional HTML comment directive, supported units and fallback behavior in other viewers.
