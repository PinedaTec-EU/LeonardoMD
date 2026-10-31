---
name: leonardo-user-guide
description: Maintain LeonardoMD bilingual illustrated user help when adding, changing or removing user-visible features, and review help coverage in feature PRs.
---

# Keep help with the feature

A feature PR must deliver its help changes in the same PR. Check the actual
menus, preferences, defaults and failure paths; do not write from a planned
feature or a successful build alone. Use `doc/guide/feature-coverage.md` to find
the affected chapter and source. Update that inventory when scope changes.

Update `doc/guide/en/body.md` and `doc/guide/es/body.md` together. Explain the
purpose, prerequisites, steps, settings scope, persistence/save destination,
limits and recovery that matter to the user. Remove obsolete instructions when
behavior changes. Review the web manual `doc/user-guide.md` for overlapping
instructions; repair affected copy within the authorized scope or identify its
canonical outstanding issue. An internal change with no visible help impact
needs a specific rationale in the PR's Help impact section, not a token doc edit.

Add or refresh images when they explain the changed flow. Use real production
components with synthetic data for UI screenshots; label diagrams as diagrams
and illustrative states accurately. Keep original PNGs and capture context /
canonical metadata in the locale's `assets/` directory. Do not edit screenshots
in place or present a component test as fresh packaged-process acceptance.
Use the shared PR delivery capture-metadata helper for new screenshots. The
opt-in `UserGuideFeatureCaptureTests` fixture captures safe initial components;
add a relevant fixture when the changed behavior needs another state. Never
pair real devices, share private documents or install updates to illustrate help.

For optional rendered content, state the required built-in extension next to
the example and explain the disabled fallback. Recommendations are limited to
our built-ins and explicit consent; document suppression and reset separately
from activation. Do not confuse renderer extensions with external AI skills.

Run `python3 scripts/package-user-guide.py` after editing help or assets. Do not
hand-edit MDLZ archives. For an updated published guide, advance document revision,
resource names and `BundledUserGuide` personal-copy directory together so existing
practice answers remain intact; update affected tests. Remove superseded bundle
resources, preserving historical evidence and user-owned copies.

Validate deterministic packages with
`python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py'`.
Run focused native `BundledUserGuideTests` through the repository's compilation
recorder, then the required full checks. Inspect both locales in actual
WKWebView, including changed images, examples and practice/save behavior. Keep
fresh review captures separate from authored instructional screenshots; record
their source SHA and any evidence-only mapping under the PR delivery contract.

Before marking the PR ready, its Help impact section must identify changed
chapters/images and validation, or justify no visible impact. During review,
missing or stale help for a changed visible behavior is an unmet acceptance
criterion. Do not replace source/content review with a blanket rule requiring
all source-file edits to touch documentation.
