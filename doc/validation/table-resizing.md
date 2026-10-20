# Preview table resizing

Tracking: [#208](https://github.com/PinedaTec-EU/LeonardoMD/issues/208).

`TableResizingTests` hosts the real `WorkspaceView` and `WKWebView` through
`swift test`; it does not launch XCTest as a standalone application. The
1100×850-point window uses two identical synthetic GFM tables and retained
Markdown front matter. Tests dispatch pointer events through the actual DOM
handles and native message handler, then validate the session and disk.

Coverage:

- Protected Preview disables controls. Click/no movement and Escape do not
  migrate. Column, row, table width, table height and corner drags commit.
- The second of identical tables receives geometry; the first remains normal.
  Migration leaves the `.md` bytes intact and saves the sibling MDLF with the
  same body and retained front matter. Subsequent changes use manual Save.
- Save cancels a provisional drag, persisted dimensions survive reopening,
  and PDF export succeeds without resize controls.
- A stale callback cannot edit a byte-identical sibling. Protected documents,
  stale content, destination collisions and authorization failure reject the
  operation without changing the original or overwriting the destination.
- `TableResizeRuntimeTests` checks keyboard resizing, native callback rejection
  and DOM rollback, zoom plus a narrower window and horizontal scrolling,
  cancellation through flush, raw HTML table exclusion and occurrence mapping,
  and source mismatch suppressing stale saved geometry.
- `LeonardoTableResizeTests` verifies round-trip/body/metadata preservation and
  invalid dimensions. Shared valid/invalid format fixtures exercise the native
  and Python validators, including zero/empty row heights and percentage height.

The supported interaction is defined in the format README. Heights are minimums,
so content can make a table taller. Table width/height and row/column geometry
use points. Source-bound geometry is invalidated by mismatching table content or
occurrence; it is not a general stable table-ID system.

## Visual evidence and reproduction

CI sets `LEONARDO_VISUAL_EVIDENCE` and `EVIDENCE_SHA` for the checked-out head.
Its `preview-tags-<SHA>` artifact includes `table-resizing/resized-reopened.png`,
`tables.pdf`, `provenance.txt` and `preview.html`. The screenshot is taken from
the real native WebKit view after migration, all resize modes, save and reopen.
Provenance records the exact head, window dimensions and state. Inspect that
capture and PDF alongside the automated geometry and source assertions.

To replay captures after compiling the current head, run one command from the
PR checkout (skip-build does not allocate another compilation-ledger delta):

```bash
EVIDENCE_SHA=$(git rev-parse HEAD) LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-table-evidence swift test --skip-build --filter TableResizingTests
```

`preview.html` is a supplemental browser harness using the same renderer assets.
Serve the checkout locally with the evidence directory available as an HTTP
route. Its resource URLs use `/Sources/LeonardoRender/Resources/`. It records
mouse commits in `window.lastTableResize` and re-enables handles for inspection;
it does not emulate native migration or disk saving. Those are proved by the
native test. The native captures are the implementation-owned visual evidence.

No fresh packaged startup, installed application update or release publication
is claimed. The owner's running application remains untouched.
