#!/bin/bash
# Operator entrypoint: execute the reviewed shared engine, never a local fork.
set -euo pipefail
cd "$(dirname "$0")/.."
engine_sha='07144074ab282217b1fb12a0e94c021763090df6'
: "${LEDGER_ENGINE_ROOT:?Set LEDGER_ENGINE_ROOT to a checkout of PinedaTec-EU/pinedatec-ci}"
engine_root=$(cd "$LEDGER_ENGINE_ROOT" && pwd -P)
test "$(git -C "$engine_root" rev-parse HEAD)" = "$engine_sha" || {
  echo "release-ledger: engine checkout must be at $engine_sha" >&2
  exit 1
}
engine_path='.github/actions/release-version-ledger'
test -z "$(git -C "$engine_root" status --porcelain --untracked-files=all -- "$engine_path")" || {
  echo 'release-ledger: engine checkout contains modified or untracked engine files' >&2
  exit 1
}
export GITHUB_WORKSPACE="$PWD"
export GITHUB_REPOSITORY='PinedaTec-EU/LeonardoMD'
export LEDGER_COMMAND="${1:?Usage: scripts/release-ledger.sh validate|validate-pr|resolve-order|calculate|materialize|record-notes}"
export LEDGER_CONFIG_PATH='deploy/version/release-ledger.json'
ledger_output=$(mktemp)
trap 'rm -f "$ledger_output"' EXIT
export GITHUB_OUTPUT="$ledger_output"
python3 "$engine_root/$engine_path/ledger.py"
cat "$ledger_output"
