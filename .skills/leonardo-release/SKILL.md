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
3. Promote the validated source to stable only after that evidence is present
   and beta findings are resolved. Publish a new higher-build stable package;
   retain the common signing key, stable-only feed and refreshed combined beta
   feed. Never relabel the beta entry or reuse its tag/build.

Compare the stable candidate with the validated beta source. Version-ledger
materialization and channel/publication metadata are expected differences;
functional code or dependency changes require another beta and acceptance.
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
