# Open Leonardo documents

Tracking: [#167](https://github.com/PinedaTec-EU/LeonardoMD/issues/167), implementation [PR #168](https://github.com/PinedaTec-EU/LeonardoMD/pull/168). Integrated in beta 0.1.435.

- Canonical public contract: [`doc/format/README.md`](../doc/format/README.md), JSON Schema and examples in the same directory. UTF-8 Markdown body plus explicit JSON front matter, `format: mdlf`, `formatVersion: 1`. Structural metadata is closed to prevent unknown properties disappearing on save; unknown versions are rejected.
- `.md` stays standard Markdown. `.mdlf` authors documents/forms; exported `.mdlr` opens in fill mode. Definitions and values live outside the body, referenced using `{{field:id}}`; extension is a mode hint, not access control.
- Core parser/types/layout/metadata validation are in focused `LeonardoFormat*` files. Draft validation permits incomplete required fields; saving a draft must retain values even when invalid.
- JSON duplicate-key validation runs before dictionary decoding, including nested opaque values and escaped key spellings. Readers share one schema for MDLF/MDLR; the response extension supplies a mode hint, while generators still mark forms explicitly.
- App document/storage classifications and package preferences are in `DocumentPresentation`; lifecycle/form adapters are in `SessionLeonardo`. Persistent chrome distinguishes format, storage and mode. Filling is independent of source protection.
- Renderer explicitly opts in through `allowsLeonardoFormat`; standard Markdown must never inherit prior Leonardo metadata. `leonardo-layout.js` applies declarative layouts and safely substitutes text values outside code. Rendered field placeholders are excluded from preview text editing.
- Preview token matching normalizes both source and MDLF body to LF, while edit offsets map back to the original bytes. Preserve this distinction so CRLF documents remain editable without rewriting untouched line endings or metadata.
- MDLZ is conventional ZIP32 (stored or DEFLATE), one root MDLF/MDLR plus `assets/`. `LeonardoPackageTransport` validates before extraction. Package mode uses a temporary workspace and conflict-aware atomic archive saves; explicit extraction saves ordinary files and requires export to repack. A successful package save returns the refreshed workspace fingerprint.
- Export rewrites resources only in its copy. Format selection and collection share the Core resource scanner, including HTML and reference-style images; do not introduce a separate UI detector. Do not rewrite answer values while moving assets. Archive paths, normalized collisions, symlinks, checksums and expansion budgets are validated.
- Mutation adapters authorize the source and destination before writing; package saves authorize the original archive before touching its temporary document. Migration flushes pending preview edits, revalidates source identity/fingerprint, and uses `DocumentStore.createNew` for exclusive destination creation.
- Package save/reload orchestration is in `SessionSaving`/`SessionReloading`. Revalidate captured identity across authorization waits; reload the original ZIP into a new workspace, never its stale temporary file. Owner and related tabs remap package identity on path changes and discard only package-owned temporary workspaces on deletion.
- `plugins/leonardo-format` contains shared Codex/Claude skill instructions and a Python transport CLI, including package creation. Follow the same versioned schema rather than inventing a separate dialect.
- Core and the CLI validate the same bundled JSON Schema plus definition/layout safety rules on reading and writing. Shared acceptance/rejection fixtures live in `Tests/FormatContractFixtures`; keep invalid draft answers transportable while rejecting unsafe definitions. Schema copies must remain byte-identical.
- The CLI uses its bundled schema by default for direct documents and archive roots in every command. Its siblings `mdlf_schema.py` and `mdlf_semantics.py` are required runtime assets; include them in downloadable plugin ZIPs. External schemas are additional restrictions, not a replacement for the canonical contract.
- Both transport implementations enforce 64 MiB archive, 32 MiB total expanded/member, and 2,048 entries. Collision keys use NFC plus full case folding; empty directory records are nonsemantic and omitted. Package/extracted rendering must use the workspace asset root even when another project is active.

Native QA must preserve the owner's installed running instance. XCTest native hosting/WebKit captures verify UI components; they do not establish fresh packaged-process readiness.

Hosted WebKit background readiness is tracked separately in [#169](https://github.com/PinedaTec-EU/LeonardoMD/issues/169). Decorative backgrounds must opt into eager loading before setting their source and retain that policy after document rendering; ordinary Markdown images may remain lazy.

Project membership must use `displayDocumentURL` (the source archive in package mode), never the temporary extracted `documentURL`. Reopening/selecting a containing project retains workspace identity and content. Regression tracking: [#170](https://github.com/PinedaTec-EU/LeonardoMD/issues/170). The shared invalid corpus also covers exact opening delimiters ([#171](https://github.com/PinedaTec-EU/LeonardoMD/issues/171)).

Extraction is an exclusive descriptor-relative transaction with no-follow traversal and device/inode ownership. Failure cleanup removes only matching created entries; temporary-workspace discard verifies its root identity. Final verification catches retargeted parents/children before the editor receives a workspace. ZIP members have at most 64 components and at most 2,048 distinct implicit parents; ambiguous canonical parent spellings are rejected. Tracking: [#172](https://github.com/PinedaTec-EU/LeonardoMD/issues/172). The plugin includes `mdlz_extract.py` and fails closed for extraction when the host lacks required POSIX capabilities.

Revocation and file operations share `workspaceIdentityURLs`, including the durable package source ([#175](https://github.com/PinedaTec-EU/LeonardoMD/issues/175)). Package retirement is centralized in `SessionPackageWorkspace`; saves own a tracked task and propagate cancellation into repacking before archive commit. Stopped sessions clear visible content immediately, join in-flight I/O, then delete temporary workspaces ([#176](https://github.com/PinedaTec-EU/LeonardoMD/issues/176)). CI capture context uses the checked-out `EVIDENCE_SHA` ([#177](https://github.com/PinedaTec-EU/LeonardoMD/issues/177)).

Accepted application/window/tab close now joins temporary retirement before exit; cancellation preserves live packages (#176). Pending document access has its own revocable identity in `SessionDocumentAccess`: revoke only the incoming load when a tab owns an unrelated draft, wait for that load to settle, and never apply its result afterward. Standard Markdown and package adapters share this boundary. Tracking: [#180](https://github.com/PinedaTec-EU/LeonardoMD/issues/180).

Format preferences share `LeonardoFormatPreferences` across sessions. Computed UserDefaults access must explicitly participate in Observation so switches and pickers refresh immediately; direct UserDefaults-only bindings do not notify SwiftUI. Regression: [#183](https://github.com/PinedaTec-EU/LeonardoMD/issues/183).

Markdown migration separates the original envelope into `values.markdownFrontMatter` (complete raw text), sets the recognized document title, and preserves edited prose bytes. Preview reuses the standard reader for retained metadata/tags instead of parsing MDLF JSON as YAML. Core conversion lives in `LeonardoMarkdownMigration`; envelope splitting is shared with `MarkdownDocumentParser`. Tracking: [#191](https://github.com/PinedaTec-EU/LeonardoMD/issues/191).

Standalone MDLF and MDLZ with inner MDLF follow the normal resolved Markdown mode (Preview by default). Standalone and packaged MDLR responses retain Fill, including explicit extraction. Explicit source-line navigation still selects Edit. Regression: [#189](https://github.com/PinedaTec-EU/LeonardoMD/issues/189).

Native background regression [#196](https://github.com/PinedaTec-EU/LeonardoMD/issues/196): with Show metadata enabled, generic Markdown parsing exposed the MDLF JSON envelope and pushed the invoice below the initial viewport; a fresh QA preference domain initially masked this. `MarkdownHTMLShell` must parse opted-in MDLF once and keep its envelope out of generic Markdown front matter. Preserve the full source for editing and typed layout for rendering; ordinary Markdown metadata remains unchanged. `doc/format/examples/invoice/invoice.mdlf` uses a separate SVG and ordinary Markdown, with no HTML. `MDLFBackgroundPreviewTests` hosts `WorkspaceView` with Show metadata explicitly on, edits a prose node through the Preview bridge, saves, reopens, checks unchanged metadata/source bytes, loads the image again and exports PDF. Do not substitute HTML-in-Markdown or a preference-off QA build as MDLF acceptance evidence. See `doc/validation/mdlf-background.md`. Migration remains in [#191](https://github.com/PinedaTec-EU/LeonardoMD/issues/191).

Boolean form controls support optional `appearance: checkbox|switch`, defaulting to checkbox. Native controls share the existing binding and disable guards; values and manual saving are unchanged. All three v1 schema copies include the hint; native and plugin semantic validators restrict it to checkbox fields. Earlier readers reject the new property. Tracking: [#198](https://github.com/PinedaTec-EU/LeonardoMD/issues/198).

Canonical metadata encoding omits default `document` and empty `fields`/`values`; explicit layout and all nested values remain intact. Both sparse and explicit-empty envelopes decode with v1 defaults. Tracking: [#204](https://github.com/PinedaTec-EU/LeonardoMD/issues/204).

Inline form filling ([#206](https://github.com/PinedaTec-EU/LeonardoMD/issues/206)) uses `leonardo-forms.js` after sanitized Markdown substitution. Preview, Split and Fill share field labels, controls and row layout; only Fill enables mutation and contextual help. Export/print retain text values ([#234](https://github.com/PinedaTec-EU/LeonardoMD/issues/234)). `MarkdownFormState` scopes cumulative field snapshots to the last rendered source, and the host acknowledges authorized native changes without redrawing focused controls. `SessionLeonardoFields` shares mode/lifecycle/read-only guards across field APIs and the bridge. Preview callbacks capture file identity and the native preview resets on URL changes, so delayed callbacks cannot mutate a byte-identical sibling file. Flush reads a fresh DOM snapshot before save/navigation. Contextual `LeonardoFieldHelp` replaces duplicate inspector inputs; (?) works for read-only fields and explains editability separately from requiredness. Self-contained full examples live in `doc/format/examples/form-showcase`. Formulas remain deferred in [#203](https://github.com/PinedaTec-EU/LeonardoMD/issues/203).

Plain Markdown export ([#216](https://github.com/PinedaTec-EU/LeonardoMD/issues/216)) uses
`LeonardoMarkdownExport` and `SessionMarkdownExport`. A native warning precedes the
save panel; the adapter flushes DOM values and reuses Leonardo export identity and
path authorization guards. Output omits metadata/layout, substitutes literal
answers in place, retains HTTP(S) images and removes nonportable sources through
the shared Core resource scanner. The original tab/file remains Leonardo.

Markdown image spans and destinations share `LeonardoMarkdownImageScanner` for
plain-copy removal, local-resource detection and portable collection. Balanced
parentheses, escaped punctuation and angle destinations use the same reader;
HTML tags use `LeonardoHTMLImageScanner` for quoted attributes and URL entities;
regression [#222](https://github.com/PinedaTec-EU/LeonardoMD/issues/222).

The native move adapter returns a discardable completion task. Package lifecycle
acceptance awaits that task instead of assuming a fixed number of `Task.yield`
iterations completes filesystem I/O ([#226](https://github.com/PinedaTec-EU/LeonardoMD/issues/226)).

External package monitoring compares the source MDLZ digest off the main actor, rather than its extracted document. Results are applied only while the complete source/extraction identity remains unchanged and no file operation is in progress, including after flushing preview edits. Clean sessions reload through the existing package workspace replacement; dirty sessions retain both versions behind the Reload/Save copy conflict choice. Tracking: [#275](https://github.com/PinedaTec-EU/LeonardoMD/issues/275).

Bundled guide (#290): `BundledUserGuide` copies localized `Guide-v4-en/es.mdlz` from Bundle.module to Application Support/LeonardoMD/User Guides/v4/<locale>, preserving existing practice answers. Help and Welcome share DocumentTabs.openUserGuide and normal external-document tab opening. Editorial sources and deterministic SVG/package generator: `doc/guide`, `scripts/package-user-guide.py`; native tests cover transport, saved-copy isolation, images and form controls. Tracking: [#290](https://github.com/PinedaTec-EU/LeonardoMD/issues/290).

Package conflict recovery ([#308](https://github.com/PinedaTec-EU/LeonardoMD/issues/308))
lives in `SessionConflictCopy.swift`. A package Save copy requires MDLZ, uses
the existing portable-resource transport and original export authorization
identity, then opens and verifies a replacement workspace before committing
the session. Preserve answers, image bytes, source archive and failure state;
text-only saving is reserved for local-document copies. Destination/source and
workspace containment checks use `ProcessFileLock.canonicalURL` for filesystem-aware
case/Unicode identity; folded coordination URLs must never be used for I/O.

Guide maintenance (#310): `doc/guide/feature-coverage.md` maps current surfaces to
19 bilingual chapters. `.skills/leonardo-user-guide/SKILL.md`, AGENTS and the PR
template require help updates with visible feature changes (or an internal-only
rationale). Locale PNGs are packaged; provenance JSON remains repository-only.
Original UI screenshots and fresh guide-render validation serve different roles.
