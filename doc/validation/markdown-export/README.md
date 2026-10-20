# Markdown export validation

Tracking: [issue #216](https://github.com/PinedaTec-EU/LeonardoMD/issues/216),
[PR #217](https://github.com/PinedaTec-EU/LeonardoMD/pull/217).

## Native warning evidence

Captured on 2026-10-20 in the macOS XCTest host with
`LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-md-evidence` and `swift test` through the
repository compilation recorder. `MarkdownExportTests` lays out the actual
`AppSession.markdownExportWarning()` NSAlert and captures its native window.

- [Spanish warning](warning-es.png)
- [English warning](warning-en.png)

Both captures show the full loss warning, Export Markdown and Cancel buttons,
without clipping. The generic folder icon belongs to the XCTest host. These
captures establish native component rendering; they do not claim a fresh
packaged application launch or an installed release. No existing application
instance was terminated.

## Behavioral coverage

`LeonardoMarkdownExportTests` covers literal values, defaults, explicit nulls,
repeated fields, GFM table safety, multiline values, image degradation and code
examples. Reference-image regressions cover local and unsupported sources,
remote sources, duplicate definitions, collapsed/shortcut forms and definitions
shared with ordinary links. Balanced/escaped/angle-delimited destinations and
nested alternative text are tested for local and remote images. Unrelated
Markdown reference definitions are preserved. Empty select labels retain the stored value.
`MarkdownExportTests` covers source preservation, path authorization,
package identity, concurrent content changes and balanced operation state.
`InlineFormTests.testMarkdownExportFlushesPendingInlineAnswersWithoutSavingOriginal`
uses real WebKit input events, exports immediately, and checks that the current
answer reaches Markdown while the original stays unchanged and dirty in memory.
