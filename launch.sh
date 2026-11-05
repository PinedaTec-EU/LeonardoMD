#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ -f .env.local ]; then
  set -a
  source .env.local
  set +a
fi
qa=false
if [ "${1:-}" = "--qa" ]; then
  qa=true
  shift
fi
./scripts/build-app.sh
app_path="$PWD/output/LeonardoMD.app"
if [ "$qa" = true ]; then
  if [ -n "${LEONARDO_QA_SIGN_IDENTITY:-}" ]; then
    app_path=$(python3 scripts/qa-bundle.py "$app_path" --sign-identity "$LEONARDO_QA_SIGN_IDENTITY")
  else
    app_path=$(python3 scripts/qa-bundle.py "$app_path")
  fi
  printf 'QA bundle: %s\nExisting LeonardoMD instances retain product-wide ownership; verify a new PID before claiming fresh startup.\n' "$app_path"
fi
python3 scripts/qa-bundle.py --verify-only "$app_path"
open -a "$app_path" "$@"
