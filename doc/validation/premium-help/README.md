# Premium bilingual help validation

Tracking: [#334](https://github.com/PinedaTec-EU/LeonardoMD/issues/334).

Captures use production WorkspaceView/WKWebView components, synthetic guide data,
and the standard image policy. All fifteen main-guide images loaded in both
languages. The standalone guide also opened/deduplicated normally; previous
main and standalone personal copies stayed untouched. The separate Mermaid
captures show that its teaching example still renders live SVG.

Capture/build source is `1cf1521` (full SHA in contexts). The following evidence
commit changes only these records and the successful compilation allocation /
release summary; no application, resource, native test or packaging input changes.
Metadata can observe the modified allocation and untracked evidence files.

The initial 1200×400 artwork plus full-size decorative cover exceeded admission.
The final layout retains all eight illustrations at 1200×400 and uses an
aspect-preserving 1024-pixel cover derivative. Original About artwork and every
existing UI screenshot remain unchanged; no renderer limit is raised. Python
checks bound the conservative whole-guide source envelope to the standard
128 MiB; final native all-image checks passed in both locales.

A full Swift suite passed before the final cover/art refinement; final
BundledUserGuideTests passed 5/5 afterward. Script/plugin/packaging suites passed
with the repository's documented skips. GitHub CI validates the final full head.
These are component captures, not fresh packaged-process startup acceptance.
No installed app was replaced or terminated. Authored illustration provenance
is separate in `doc/guide/<locale>/assets`; those images are generated diagrams,
not UI screenshots. Original PNGs, observed contexts and shared-helper metadata
are retained here without retouching.
