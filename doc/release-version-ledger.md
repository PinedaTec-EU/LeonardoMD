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

Use an English issue-linked title, e.g. `#38 Added: adopt release version ledger`.
The title is the release-note summary; the body contains implementation and
validation detail. The central renderer uses the verified title, not a copied
or inferred summary of the PR body.

## Shared engine operation

The engine remains in `PinedaTec-EU/pinedatec-ci`, pinned to integrated commit
`4ff32120218cdd58d019fcd3f70e51bc0fdb63f6`; do not copy it or use a mutable pin.
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

After the source PR merges into main, run the engine's `resolve-order` with
read-only `LEDGER_SOURCE_TOKEN` and external `LEDGER_OUTPUT_PATH`. Inspect the
integration-order JSON before selecting `calculate` with
`LEDGER_INTEGRATION_ORDER_PATH`. Inspect the chosen PR/version before invoking
`materialize` in an isolated checkout from current main. Propose its output in
a separate reviewed PR on `codex/ledger-version-<source-pr>` with exact title and squash subject
`v.<version> (#<source-pr>)`. Only the version output, checkpoint and deletion
of the consumed entry may change. Validate and integrate this PR before
publishing the corresponding release. Never materialize unmerged entries or
write directly to main.

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

The engine creates `deploy/release-notes.md` only after acceptance. Notes group
by release/feature and preserve full versions. Open a reviewed notes-only PR on `codex/ledger-notes-<source-pr>` with
exact title/squash subject `Release notes for <version> (#<source-pr>)`; its
body identifies the release and evidence URL. Validate it with `validate-pr`
in `notes` mode and read-only evidence/source tokens. Do not invent historic
release summaries for the initial baseline.

## Trusted policy and activation dependencies

The integrated-base `pull_request_target` workflow runs read-only
`release-ledger-scope`, checking out PR data and executing only the immutable
central engine. It rejects the reserved engine path before/after candidate
checkout, including symlinks. Automatic branches are Bot-only; same-repository
operator branches `codex/ledger-version-*` and `codex/ledger-notes-*` invoke the
corresponding strict central mode, so manually proposed engine output remains
subject to exact title/scope/arithmetic or accepted-evidence checks.
No candidate script or local Action is executed in this privileged workflow.

LeonardoMD is public and pinedatec-ci is private; native private Action sharing
cannot supply the engine here. The policy checkout requires
`RELEASE_LEDGER_ENGINE_TOKEN`, a fine-grained credential with **contents: read
only for pinedatec-ci**, with credential persistence disabled. The credential
reaches only the engine checkout and is not given to PR code or publication.
Missing access fails explicitly. This adoption does not provision credentials.
After integration, observe a successful exact-head policy run and require
`release-ledger-scope` in branch rules. First adoption needs external trusted
engine validation and independent review because its target workflow cannot
execute from the base before integration.

Automatic writers are still pending: the existing central App publisher accepts
private targets and has no LeonardoMD registration. Local operator execution
of the shared engine is available. Complete public-target support, App access,
target registration and exact-head check binding before enabling automatic
materialization/notes writers. Do not add local App private keys or claim a
schedule is active. Reserve `release-ledger-policy` for the central App check.

## Skill discovery

`AGENTS.md` routes through generated `.skills/index.md`. Recurring release work
references `release-version-ledger`, `shared-skills-bootstrap`, `release-cleanup`
and `deployment-target-validation`, alongside existing Git, issue, review and
memory skills. Adapters link to canonical `../ai-skills-shared`; no shared skill
body is copied into this repository.

Tracking: [#38](https://github.com/PinedaTec-EU/LeonardoMD/issues/38).

## Signed update packaging

Sparkle configuration preserves the generated canonical bundle version/build. Explicit release environment values must match them; beta labels may append `-beta.N` without changing the canonical build. Advance the ledger build before publishing another beta or stable package. Feed isolation, signature verification and notarization gates remain in the [signed release workflow](releases.md).
