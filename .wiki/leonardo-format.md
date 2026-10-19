# Open Leonardo documents

Tracking: [#167](https://github.com/PinedaTec-EU/LeonardoMD/issues/167), implementation [PR #168](https://github.com/PinedaTec-EU/LeonardoMD/pull/168). The work is under validation; this page does not claim release or integration.

- Canonical public contract: [`doc/format/README.md`](../doc/format/README.md), JSON Schema and examples in the same directory. UTF-8 Markdown body plus explicit JSON front matter, `format: mdlf`, `formatVersion: 1`. Structural metadata is closed to prevent unknown properties disappearing on save; unknown versions are rejected.
- `.md` stays standard Markdown. `.mdlf` authors documents/forms; exported `.mdlr` opens in fill mode. Definitions and values live outside the body, referenced using `{{field:id}}`; extension is a mode hint, not access control.
- Core parser/types/layout/metadata validation are in focused `LeonardoFormat*` files. Draft validation permits incomplete required fields; saving a draft must retain values even when invalid.
- App document/storage classifications and package preferences are in `DocumentPresentation`; lifecycle/form adapters are in `SessionLeonardo`. Persistent chrome distinguishes format, storage and mode. Filling is independent of source protection.
- Renderer explicitly opts in through `allowsLeonardoFormat`; standard Markdown must never inherit prior Leonardo metadata. `leonardo-layout.js` applies declarative layouts and safely substitutes text values outside code. Rendered field placeholders are excluded from preview text editing.
- MDLZ is conventional ZIP32 (stored or DEFLATE), one root MDLF/MDLR plus `assets/`. `LeonardoPackageTransport` validates before extraction. Package mode uses a temporary workspace and conflict-aware atomic archive saves; explicit extraction saves ordinary files and requires export to repack. A successful package save returns the refreshed workspace fingerprint.
- Export rewrites resources only in its copy. Do not rewrite answer values while moving assets. Archive paths, normalized collisions, symlinks, checksums and expansion budgets are validated.
- `plugins/leonardo-format` contains shared Codex/Claude skill instructions and a Python transport CLI, including package creation. Follow the same versioned schema rather than inventing a separate dialect.

Native QA must preserve the owner's installed running instance. XCTest native hosting/WebKit captures verify UI components; they do not establish fresh packaged-process readiness.
