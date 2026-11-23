---
name: leonardo-release
description: Prepare, publish or promote LeonardoMD macOS releases through accepted PR, validated beta and stable, with explicit owner exceptions to the beta stage.
---

# LeonardoMD release progression

Use for LeonardoMD release preparation, publication or stable promotion. Read
[the release contract](../../doc/releases.md), including its acceptance matrix,
before selecting a publication channel. This is repository-specific policy;
do not modify shared merge or version-ledger skills to enforce it elsewhere.

## Normal progression

1. Integrate an issue-linked PR into `main` with exact-head CI and independent
   review satisfied under the repository delivery workflow. Materialize its
   numeric ledger version before preparing distribution assets.
2. Prepare and publish a signed, notarized beta as a GitHub prerelease. Verify
   the public archive and combined beta subscription feed, then record actual
   update, install and relaunch acceptance against its immutable source SHA,
   numeric version/build, tag and archive digest in the canonical issue.
3. Promote the exact validated beta artifact to stable only after that evidence
   is present and beta findings are resolved. Use `promote-beta.yml` with its
   explicit tag, source SHA, structured owner acceptance URL and request ID.
   The trusted central promoter retains the numeric version, tag, build and
   signed/notarized ZIP bytes, stages stable publication metadata and refreshes
   the combined beta feed before making that release stable/latest.
   Then complete the maintainer-Mac signed installed-maturity assertion described
   in `doc/releases.md` using `scripts/publish-release-maturity.py`; verify its
   public readback before claiming installed-promotion recognition is available.

Read the shared candidate-promotion convention and the central executable
contract at `pinedatec-ci/docs/release-candidate-promotion.md`. Do not create a
promotion-only PR, ledger delta, new build, tag or compilation. Existing
`scripts/release-promotions/<PR>.json` records document historical publication
and must remain unchanged. Implementing promotion machinery still uses normal
issue-linked PR/CI/judge and source compilation-count rules.

The selected beta tag must still resolve to its accepted source and every
downloaded asset must match owner-accepted hashes. The central Sparkle adapter
also verifies the ZIP signature, pinned key and packaged version/build. Only
publication metadata changes; a rebuilt binary, functional or dependency change
requires another candidate and acceptance.
A local candidate, green CI or an unvalidated public beta is insufficient
evidence for normal stable promotion. Keep publication authorization separate
from PR merge authorization; a request to change this skill publishes nothing.

## Explicit exception

The owner may explicitly authorize skipping the beta stage for a named
version/source SHA or a bounded publication request. If the request leaves
the candidate ambiguous, resolve that identity before publication. A generic
request to release, merge a PR, or use this skill does not waive beta.

Before publishing, record the direct owner instruction, candidate identity,
skipped stage, reason (owner-provided, or explicitly unspecified), missing beta
evidence, residual risk and required follow-up in the canonical issue and
publication record. The instruction “publish this candidate directly as
stable, skipping beta” is sufficient; do not ask for repeated authorization.
Treat the exception as limited to that candidate/request, never a permanent
change of default. Disclose the lack of beta acceptance without claiming it
passed. This policy itself does not authorize an exception for the current PR.

Skipping beta does not waive PR integration, exact-head CI/review, numeric
build ordering, signatures, notarization, archive verification, feed isolation
or release acceptance required by the release contract. Do not override
branch protection, unresolved technical failures or credential/target gates.
Apply the existing operational-blocker workflow for unavailable validations;
the channel exception alone is not approval to skip those validations.
