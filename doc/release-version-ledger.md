# Release version ledger

LeonardoMD adopts the shared immutable ledger with owner-approved baseline
**0.1.56**. This seed is not a published release or reconstructed history.
`version.nfo` is the canonical `release.feature.build` artifact; the checkpoint
`deploy/version/version.yaml` starts with empty applied history.

## Packaged metadata

`scripts/Info.plist` no longer maintains independent version fields.
`scripts/package-version.py` derives `CFBundleShortVersionString` from the
canonical version and `CFBundleVersion` from its build component (initially
`56`). This explicitly replaces `0.1.0` / build `1`. Build counts successful Swift compilation commands recorded for the source PR,
not PRs, commits, arbitrary CI jobs or inferred retries. Release/feature advances
are explicit delivery decisions and do not reset lower counters. The shared
engine adds the recorded deltas without resetting components. The supported macOS build range is 1–9999; changing that
representation requires a reviewed migration. About and startup diagnostics
read the generated bundle; direct SwiftPM execution remains a development build.

## Source PR policy

Sources, resources, tests, package manifests, startup/packaging scripts and CI
require one new `deploy/version/entries/<PR>.yaml`, after GitHub assigns the PR
number. A single successful recorded compilation produces:

```json
{"build": 1}
```

Release/feature increments require an explicit delivery decision. They preserve
build unless the PR also records successful compilation commands. Documentation, wiki and skill-reference-only changes are exempt.
Do not edit another PR's pending entry. Ordinary source PRs cannot change
`version.nfo`, checkpoint or generated release notes. First adoption alone
seeds the artifact/checkpoint and includes its recorded compilation delta; its
first candidate is `0.1.(56 + recorded build delta)` rather than a fixed +1.

Use `scripts/compile-and-record.py --pr-number <PR> -- swift build|test|run`
for source-PR compilation commands. The wrapper executes the command and adds
one build only after success, preserves existing release/feature deltas, and
serializes atomic entry updates. Failed commands and metadata-only queries do
not increment it. Setting `LEONARDO_SOURCE_PR=<PR>` when running
`scripts/build-app.sh` records its one release build; its `--show-bin-path` query
is excluded. Commit the updated entry before final validation. First adoption
validates the committed delta externally against the pinned trusted engine;
ordinary GitHub CI runs packaging/recorder tests and skips engine-backed tests
without private engine access. After integration and engine access/check binding,
the trusted policy job verifies each committed entry. CI does not write deltas
or infer counts from jobs/retries.
Main builds without a pending source PR do not allocate a source-PR delta.

Stable promotion is a separate explicit publication event. Use Actions → Request
promotion of a concrete beta with its exact tag/SHA, structured owner acceptance
URL and request ID. The central promoter preserves the accepted version/build,
tag and ZIP; no new source PR, compilation, delta or materialization is needed
for the channel operation. Main may contain later beta code without affecting
this selection. Existing `scripts/release-promotions/<PR>.json` files are
historical inputs from the former higher-build promotion flow; preserve them,
but do not create new ones. Machinery changes remain ordinary source work.

The [central contract](https://github.com/PinedaTec-EU/pinedatec-ci/blob/main/docs/release-candidate-promotion.md)
defines the exact request/acceptance schemas, signature and source checks,
recoverable metadata staging, replay rules and terminal publication evidence.

Use an English issue-linked title, e.g. `#38 Added: adopt release version ledger`.
Every versioned source PR supplies a reviewed `summary` in its own delta entry:
1–280 characters of single-line plain text describing observable changes. Keep
implementation and validation details in the PR body, with a matching `Release
summary` section. The central engine preserves that exact text alongside the PR
identity and renders it beneath the verified title; it never infers a summary
from the title or body. PR #210 is the explicit historical adoption boundary;
trusted validation also requires a summary on revived older source PRs.
The compilation recorder retains summary metadata while incrementing `build`.

## Shared engine operation

The engine remains in `PinedaTec-EU/pinedatec-ci`, pinned to integrated commit
`d5bf9cbf0b5a2c92dfb6fafa24e718fa3fcedebe`; do not copy it or use a mutable pin.
`scripts/release-ledger.sh` is a thin operator entrypoint. Set
`LEDGER_ENGINE_ROOT` to a clean checkout at that exact revision. It checks the
revision and engine working tree, passes the workspace to the shared engine,
and prints its outputs. Credentials stay in the operator environment.

Start with this read-only gate:

```bash
LEDGER_ENGINE_ROOT=/absolute/path/to/pinedatec-ci ./scripts/release-ledger.sh validate
```

Inspect the output before advancing. For source-PR `validate-pr`, supply
`LEDGER_PULL_REQUEST_NUMBER`, `LEDGER_PULL_REQUEST_TITLE`, `LEDGER_BASE_SHA`
and `LEDGER_HEAD_SHA`; validation examines committed data and full SHAs.

## Automatic processing after source integration

`.github/workflows/request-release-ledger-publication.yml` follows the
[ARX adapter](https://github.com/PinedaTec-EU/kopernicus-arx/blob/main/.github/workflows/request-release-ledger-publication.yml)
and the [central dispatch contract](https://github.com/PinedaTec-EU/pinedatec-ci/blob/main/docs/consumer-release-ledger-dispatch.md).
The trusted `pull_request_target: closed` event requests processing only for
merged source PRs into `main` in `PinedaTec-EU/LeonardoMD`. Unmerged closures
and the catalog's `automation/release-version-ledger` and
`automation/release-notes` branches are excluded to prevent recursive requests.
No checkout, candidate code execution or publisher App credential is needed.

The Ubuntu-hosted job uses the existing `PINEDATEC_CI_DISPATCH_TOKEN` to send
`repository_dispatch` (event type `private-release-ledger`) to
`PinedaTec-EU/pinedatec-ci`, with canonical `target_repository`, `operation: all`
and a repository/PR/run correlation ID. This is the same transport as ARX;
it is not a direct `workflow_dispatch`. Missing credentials or API failure fail
the request. Reruns and the central 15-minute scheduler recover pending work.
The catalog already enables LeonardoMD; this adapter changes no activation.

The central pinned engine and serialized App writer consume merged entries in
integration order and write version metadata and prepared notes directly with
expected-head protection. Generated commits include `[skip ci]`, so the
existing push/PR product CI remains unchanged and does not rerun for those
updates. Source PR CI and exact-head policy/review gates remain required.
Generated updates require no draft PR or manual review transition. Operator
materialization helpers remain recovery tools, not the automatic delivery path.

`deploy/release-notes.prepared.md` contains verified source changes for the
materialized versions, without asserting publication. Evidence-backed accepted
notes remain in `deploy/release-notes.md`. A successful merge or dispatch is
neither an accepted release nor proof that the writer updated main.

Verify a subsequent source merge with the consumer request-run URL, correlated
central run and actual version/prepared-notes commit. Do not rely on the first
adapter merge to execute its new base-owned workflow. Central rollout and App
write capability remain tracked under
[pinedatec-ci#294](https://github.com/PinedaTec-EU/pinedatec-ci/issues/294).
Consumer tracking: [#69](https://github.com/PinedaTec-EU/LeonardoMD/issues/69).

## Accepted publication and notes

The accepted event is a published, non-draft, non-prerelease GitHub Release in
`PinedaTec-EU/LeonardoMD`, tagged `v{version}`, resolving to the source SHA
carrying that materialized version. A merge, tag, successful build or draft is
not publication. `require_applied_version: true` rejects seed-only notes.

After publication is confirmed, use `record-notes` with external
`LEDGER_EVIDENCE_PATH`. Its JSON must contain exactly `schema_version: 1`,
`kind: github_release`, `repository`, numeric `release_id`, `tag_name`, full
`source_sha`, `version` and `evidence_url`. The release tag must already exist
locally. Read-only `LEDGER_EVIDENCE_TOKEN` verifies release access and
`LEDGER_SOURCE_TOKEN` verifies the merged source PR. The engine checks the live
release, tag SHA, version and PR provenance, and renders the verified PR title,
PR link, merge SHA and delta. Retries must not duplicate accepted notes.

The engine creates `deploy/release-notes.md` only after acceptance. Materialized versions without a GitHub Release are intermediate checkpoints, not historical publications. The next accepted release accumulates their verified source changes since the previous accepted event. An earlier matching stable draft remains a pending publication and blocks later notes until it publishes. Do not backfill fictitious Releases; older publication after newer accepted notes remains rejected. Notes group by release/feature and preserve full versions. The automatic
central writer changes only the configured accepted-notes artifact after
verification; legacy notes-only PR tooling remains an operator recovery path.
Do not invent historic release summaries for the initial baseline.

## Trusted policy and activation dependencies

The integrated-base `pull_request_target` workflow requests central validation
using `PINEDATEC_CI_DISPATCH_TOKEN`, following the sibling consumers' dispatch
contract. It runs on GitHub-hosted Ubuntu with no checkout, executes no PR code,
and ignores drafts, forks and non-main targets. The token is sent only to the
`PinedaTec-EU/pinedatec-ci` repository dispatch endpoint. A dispatch acknowledgement
is not a validation verdict. The App-owned `release-ledger-policy` check on the
exact source SHA is authoritative; require that check with App ID `4862830`
before source integration. No `RELEASE_LEDGER_ENGINE_TOKEN` is required.

Public consumers cannot directly reference a private Action or reusable workflow.
The private central workflow instead loads its own trusted engine and reads the
public consumer as data. The central catalog must allowlist LeonardoMD and its
App installation must grant the existing scoped policy permissions for this
repository. Public visibility does not grant fork code access to credentials.

Central public-target support and catalog registration are integrated. Owner policy keeps `main` without native branch protection or rulesets. Before every source PR merge, the delivery workflow must verify successful exact-head Actions `test` (App `15368`) and `release-ledger-policy` (App `4862830`), freshness against current main, and a strict fresh-agent judge PASS. These are mandatory process gates; GitHub does not enforce them through branch settings. The configured dispatch token was exercised on #56; #62 and #63 proved successive serial materialization.

For legacy generated-PR recovery, keep GitHub automatic branch deletion enabled. After each generated PR merges, verify its remote ref is absent before requesting the next materialization; otherwise a stale branch can correctly fail the engine safety preflight. If a retired ref remains, check that no open PR uses it, delete only its verified SHA with a lease, and preserve any advanced ref. Recovery and automatic cleanup were verified in [#61](https://github.com/PinedaTec-EU/LeonardoMD/issues/61).

The automatic App writer requires default-branch write capability in the central
installation. Consumer dispatch alone does not prove that capability; rollout
verification remains under [central #294](https://github.com/PinedaTec-EU/pinedatec-ci/issues/294).
Legacy generated-PR automatic merge permissions were tracked separately under
[pinedatec-ci#279](https://github.com/PinedaTec-EU/pinedatec-ci/issues/279).
Version/prepared-note writes preserve the accepted-publication evidence gate.

## Skill discovery

`AGENTS.md` routes through generated `.skills/index.md`. Recurring release work
references `release-version-ledger`, `shared-skills-bootstrap`, `release-cleanup`
and `deployment-target-validation`, alongside existing Git, issue, review and
memory skills. Adapters link to canonical `../ai-skills-shared`; no shared skill
body is copied into this repository.

Tracking: [#38](https://github.com/PinedaTec-EU/LeonardoMD/issues/38).

## Signed update packaging

Sparkle configuration preserves the generated canonical bundle version/build. Explicit release environment values must match them; every channel uses the same numeric version with no beta/alpha/maturity suffixes. Advance the ledger build before publishing a newly built beta or stable package. Promoting the same accepted ZIP retains its canonical version/build and uses the explicit publication event instead. Feed isolation, signature verification and notarization gates remain in the [signed release workflow](releases.md).

## Pin maintenance

Refresh the immutable engine SHA after engine changes integrate into central main, through reviewed source PRs in the central catalog and this operator wrapper. Validate both against the same integrated snapshot; publisher-only commits with an unchanged engine tree do not require recursive pin refreshes. Never resolve mutable main at execution time. Apply the same mandatory exact-head process gates to every operator, including administrators; do not enable branch protection as a merge prerequisite. Dispatch-token execution was observed on PR #56 after readiness. Tracking: [#38](https://github.com/PinedaTec-EU/LeonardoMD/issues/38).

Integrate the central catalog refresh before enabling policy validation of the consumer pin PR. An App verdict binds the head, base and engine identity; if a queued run already recorded the old pin on that head, refresh the consumer head and obtain new current-pin validation instead of overwriting the immutable verdict.

Publish the final consumer pin PR head only after the central catalog refresh integrates: queue inventory can validate drafts too. If an older engine already issued a check, refresh the consumer head after catalog integration and verify the new binding.

## Owner policy and sibling audit

On 2026-10-09 the owner explicitly confirmed that main must remain unprotected. Read-only GitHub API inspection of all 41 PinedaTec-EU repositories found `main.protected=false` in every repository. All 31 private repositories returned HTTP 403 for protection/rulesets with the provider message requiring a plan upgrade or public visibility; the organization reports the free plan. The 10 public repositories have no active rulesets. Public LeonardoMD can technically enable protection, but the owner chooses the same unprotected-main policy. Absence of native protection is not itself a merge rejection under this local contract. Passing CI, exact-head ledger validation, owner authorization and independent judgment remain mandatory. Without native enforcement, another actor can bypass these process gates; this audit does not claim equivalent provider enforcement.

Tracking: [#81](https://github.com/PinedaTec-EU/LeonardoMD/issues/81).

## Native release notes

CI inspects the real app after packaging with `scripts/qa-bundle.py --verify-only --report`.
The `release-notes-package-<SHA>` artifact records the checkout, executable,
dependencies, signature check, canonical bundle/version and byte-identical JSON hash.
It does not claim a process launch. Native capture evidence includes interval and
downgrade states in both languages and themes.

`version.changes_output_path` opts into the central `deploy/release-changes.json`
artifact. It is generated and validated by the pinned shared engine in the same
materialization as `version.nfo`; consumer code does not calculate or invent
release history. The optional `export-changes` command seeds this output at the
current materialized version during adoption. Historical changes retain their
original provenance and may have no detailed summary.

`scripts/build-app.sh` copies the central JSON into
`Contents/Resources/ReleaseChanges.json` through `package-release-changes.py`,
which rejects a different canonical version or repository and preserves bytes.
Native loading additionally validates the complete version chain, source
identities, deltas and plain-text summaries. Beta and stable builds both carry
materialized changes without pretending an accepted publication occurred.

After the first primary-process window and pending Finder opens are ready,
Leonardo presents a scrollable native notice before the default-application
startup prompt. Forwarded launches do not reopen it. The application menu’s
`Release notes…` action always permits manual access. The notice defaults
`Do not show again for this version` to enabled for each newly presented version.
Closing by Done or the title-bar button persists that choice; disabling it allows
repeat presentation on later launches of that version. Suppression is per version,
not a global opt-out. Newer versions show all accumulated changes since the prior
presented version. Repeated notices retain that same interval. First use or an
unknown baseline explicitly shows available recorded history. A downgrade labels
its earlier history instead of calling removed changes newly added.

Preferences use isolated UserDefaults state under `releaseNotesPresentation.v1`.
No network request is needed to show notes. A missing/invalid artifact does not
interrupt startup and manual access explains its unavailability; normal packaging
rejects identity drift before signing.

Tracking: [#209](https://github.com/PinedaTec-EU/LeonardoMD/issues/209).
