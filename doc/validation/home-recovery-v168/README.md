# PR #516 Guide v168 capture evidence

The implementation-owned captures show the exact Packaged Guide v168 Home
chapter in [English](guide-v168-home-en.png) and [Spanish](guide-v168-home-es.png).
Both include the unavailable-item workflow and the replacement validation
paragraph. The source is `6c84f6ea040dcfa702dd6807eabf4a5c7240f1b2`. The sidecars
record image and package SHA-256, Chromium version, viewport and capture state.
This evidence-only branch changes no product files.

These are Chromium captures of the actual bundled MDLZ packages served
read-only by an isolated, task-owned local preview worker. They are separate
from the prior real native Help and Home workflow views in the PR's
`doc/validation/home-recovery-v150` record. Current packaged Help routes in
`BundledUserGuide.swift` use the same implementation with new resource names
and personal-copy revision. The browser capture does not claim the current
native Help menu was exercised.
