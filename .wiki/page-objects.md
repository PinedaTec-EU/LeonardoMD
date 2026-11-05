# Page objects and rubrics

Tracking: [#193](https://github.com/PinedaTec-EU/LeonardoMD/issues/193),
[PR #316](https://github.com/PinedaTec-EU/LeonardoMD/pull/316).

`LeonardoGraphic` adds independent `layout.objects`: one image source or
platform-independent `LeonardoRubric`, page plus point XY/size, signed integer Z.
Text is zero, array order breaks equal-Z ties (first behind). Backgrounds are
separate. Keep schema copies and Python semantics aligned. Draft rubric answers
stay opaque/transportable, but render only after bounded ink validation.

`<!-- leonardo:page-break -->` is an exact standalone block token, not a code
sample. Page-object documents paginate by block with physical point surfaces.
Oversized blocks mark overflow and prevent silent PDF cropping. The editor
owns readjustment after text changes. `leonardo-objects.js` reflows retained
DOM nodes after extension/image readiness; PDF geometry is captured before
restoring preview presentation. `MarkdownPagePDF` crops into physical vector
pages; ordinary continuous-document PDF retains the existing path.

`SessionGraphics` shares history/protection/identity with ordinary edits.
Field rubric dialogs use the acknowledged form baseline, not stale DOM source.
Geometry messages may not replace ink or image resources. `GraphicImageImport`
decodes bounded images off-main; `GraphicAssetStore` writes exclusively under
`assets/` using no-follow directory descriptors. Root-level assets break MDLZ
save: keep imports under assets and use canonical portable resource collection.

`RubricEditor` is a native canvas; menu creation always saves labeled ink to
`RubricLibrary`. Form creation can opt into that library; selected saved ink is
copied. Library and session are injectable for isolated tests/captures. No sync,
pressure requirement, Preview private-store access or cryptographic signing.

`DocumentToolbar` groups commands and uses a mode dropdown. Floating controls
live beside selection as a read-only X/Y/Z summary with Inspect. `GraphicInspector`
uses the existing workspace right-hand slot for geometry, Z, color and deletion.
`SessionGraphicInspection` validates the current object snapshot before mutation;
recoloring preserves library ink and all other stroke properties. Native selection
state is carried through render payloads; document capture listeners clear it on
outside pointer, text selection and Escape. Clear notifications remain safe during
a pending render and must never be dropped or resurrect selection. Native inspector
focus is outside the DOM and retains selection. Mode/protection/document switches
clear it. Tracking: [#323](https://github.com/PinedaTec-EU/LeonardoMD/issues/323),
[#322](https://github.com/PinedaTec-EU/LeonardoMD/issues/322). More → Objects
selects obscured images. Bilingual help is Guide v8; generated references and
native component evidence must not be confused with packaged-process acceptance.

The local rubric library serializes read-latest mutations with a nonblocking stable sidecar lock across app instances; a busy or corrupt library is never overwritten. Opening the editor refreshes its list. Regression tracked in [#318](https://github.com/PinedaTec-EU/LeonardoMD/issues/318).
