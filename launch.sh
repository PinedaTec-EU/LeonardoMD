#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ -f .env.local ]; then
  set -a
  source .env.local
  set +a
fi
./scripts/build-app.sh
open -a "$PWD/output/LeonardoMD.app" "$@"
