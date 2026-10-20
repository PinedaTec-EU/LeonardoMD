# Local image loading and representation

Tracking: [#243](https://github.com/PinedaTec-EU/LeonardoMD/issues/243).

The document URL scheme admits disk and immutable in-memory images through the
same serial background loader. Disk reads check the open regular-file descriptor
and remain bounded if the file grows. Cancellation stops delivery to retired
WebKit requests; native codec calls themselves are not interruptible mid-call.

## Resource policy

| Resource | Limit / behavior |
| --- | --- |
| Input | 32 MiB per raster; 2 MiB per SVG |
| Source raster | 40 million pixels, inspected before thumbnail decoding |
| Static preview | Viewport × display scale × current page zoom, capped at 4096 pixels per side and 4 million pixels |
| PDF raster | Displayed CSS bounds × 300/96, capped at 8192 pixels per side and 16 million pixels |
| Animation | Original bytes; up to 128 frames and 4 million total logical-canvas pixels |
| Document render | 128 MiB estimated admitted cost and 256 distinct resource/content/target variants |
| Pending work | 32 requests per view; one loader operation at a time |

ImageIO creates static thumbnails without caching the full source image, and
returns PNG to preserve alpha. Original files and corpus data remain unchanged.
PDF preparation waits for the selected higher-resolution variants, preserves
layout dimensions, and restores preview source selection and styles afterward.
A rejected image shows its authored alt text (or an unavailable label); PDF
export fails instead of silently omitting it.

Admission resets on a new document render. Repeated loads of the same resource,
content and target share admission; distinct paths or changed bytes count again.
The loader retains hashes and accounting only, with no additional image cache.

## Regression coverage and evidence

- `MarkdownImageLoaderTests`: oversized sparse disk files and memory inputs,
  regular-file enforcement, source-pixel limits, downsampling, independent PDF
  resolution, animation preservation and limits, SVG limits, repeat admission,
  document-generation reset and cancellation.
- `MarkdownImageSchemeTests`: queue limit, stop and teardown without late callbacks.
- `WebKitRuntimeTests`: real raster preview and PDF resolution, source/style
  restoration, visible rejection fallback, export failure on missing assets,
  and existing offline SVG/background behavior.
- With `LEONARDO_VISUAL_EVIDENCE` set, WebKit tests capture
  `bounded-raster-preview.png` and `bounded-image-fallback.png`. The existing CI
  preview evidence artifact binds those captures to the reviewed head.

Local validation on 2026-10-20: full `swift test` passed 571 tests with 15
intentional XCTest skips. Script tests ran 31 cases with seven engine-dependent
skips and no failures. The per-PR ledger records four successful compiler-bearing
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
