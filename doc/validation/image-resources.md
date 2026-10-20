# Local image loading and representation

Tracking: [#243](https://github.com/PinedaTec-EU/LeonardoMD/issues/243).

The document URL scheme admits disk and immutable in-memory images through the
same serial background loader. Disk reads check the open regular-file descriptor
and remain bounded if the file grows. Cancellation stops delivery to retired
WebKit requests; native codec calls themselves are not interruptible mid-call.

## Resource policy

| Resource | Limit / behavior |
| --- | --- |
| URL metadata | 16 KiB per request |
| Input | 32 MiB per raster; 2 MiB per SVG |
| Source raster | 40 million pixels, inspected before thumbnail decoding |
| Static preview | Viewport × display scale × current page zoom, capped at 4096 pixels per side and 4 million pixels |
| PDF raster | Displayed CSS bounds × 300/96, capped at 8192 pixels per side and 16 million pixels |
| Animation | Original bytes; up to 128 frames and 4 million total logical-canvas pixels |
| Document render | 128 MiB estimated admitted cost and 256 distinct resource/content/target variants |
| Pending work | 256 requests per view; one loader operation at a time |

ImageIO creates static thumbnails without caching the full source image, and
returns PNG to preserve alpha. Original files and corpus data remain unchanged.
PDF preparation waits for the selected higher-resolution variants, preserves
layout dimensions, and restores preview source selection and styles afterward.
PDF exports are serialized per host; restoration finishes before the next caller
can prepare image variants. Cancelled queued callers release their place.
A rejected image shows its authored alt text (or an unavailable label); PDF
export fails instead of silently omitting it.

Admission resets on a new document render. Pending image loads may be reused
by WebKit across incremental DOM updates; they complete normally unless WebKit
stops them or the view is torn down. Older pending requests use the current
admission budget without rolling its generation backward. Repeated loads of the same resource,
content and target share admission; distinct URLs (including query parameters)
or changed bytes count again.
The loader retains hashes and accounting only, with no additional image cache.

## Regression coverage and evidence

- `MarkdownImageLoaderTests`: canonical BMP/TIFF/ICO disk and memory compatibility, oversized sparse disk files and memory inputs,
  regular-file enforcement, source-pixel limits, downsampling, independent PDF
  resolution, animation preservation and limits, SVG limits, repeat admission,
  document-generation reset, query-alias accounting, bounded URL metadata and cancellation.
- `MarkdownImageSchemeTests`: queue limit, active-load completion across render updates, stop and teardown
  without late callbacks.
- `WebKitRuntimeTests`: production memory-asset BMP/TIF/TIFF/ICO preview and PDF, real raster preview and PDF resolution, source/style
  restoration, overlapping exports with queued cancellation, visible rejection fallback, export failure on missing assets,
  64 small images in one request burst, and existing offline SVG/background behavior.
- With `LEONARDO_VISUAL_EVIDENCE` set, WebKit tests capture
  `bounded-raster-preview.png`, `bounded-image-fallback.png` and
  `bounded-memory-formats.png`. The existing CI
  preview evidence artifact binds those captures to the reviewed head.

Local validation on 2026-10-20: full `swift test` passed 497 tests with 14
intentional XCTest skips. Script tests ran 32 cases with seven engine-dependent
skips and no failures. The per-PR ledger records eighteen successful compiler-bearing
invocations; required exact-head CI and independent judgment are recorded on PR
[#245](https://github.com/PinedaTec-EU/LeonardoMD/pull/245).

## Scope and measurement limits

The budget is an admission estimate using up to eight bytes per raster pixel,
not a bound on total process resident memory. ImageIO/WebKit internals, multiple
views and transient old/new document overlap can add memory. Existing immutable
corpus bytes are already allocated before this loading boundary. SVG remains
vector: input size and estimated surface are bounded, but arbitrary filter/path
complexity is not modeled. Remote and data URLs do not traverse this scheme.
Preview variants are selected when requested; later window/zoom changes do not
automatically reload images. Hard admission limits also apply during export, so
large documents may require smaller assets. No packaged-app startup or measured
peak-memory claim is made by these component tests.
