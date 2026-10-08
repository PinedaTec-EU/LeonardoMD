#!/bin/bash
# Keep at least one argument before expansion: Bash 3.2 rejects empty arrays with nounset.
set -euo pipefail
: "${1:?Sparkle generate_appcast tool required}"
: "${2:?Assets directory required}"
: "${3:?Release channel required}"
: "${4:?Release version required}"
: "${5:?Keychain account required}"
arguments=(--account "$5" --embed-release-notes --download-url-prefix "https://github.com/PinedaTec-EU/LeonardoMD/releases/download/v$4/")
case "$3" in
  stable) ;;
  beta) arguments+=(--channel beta) ;;
  *) echo 'Unknown release channel' >&2; exit 1 ;;
esac
"$1" "${arguments[@]}" "$2"
python3 "$(dirname "$0")/verify-release-appcast.py" "$2/appcast.xml" "$3" --bind
