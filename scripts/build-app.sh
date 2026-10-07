#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${LEONARDO_SOURCE_PR:-}" ]]; then
  python3 scripts/compile-and-record.py --pr-number "$LEONARDO_SOURCE_PR" -- swift build -c release
else
  swift build -c release
fi
bin_dir=$(swift build -c release --show-bin-path)
app_dir="$PWD/output/LeonardoMD.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/LeonardoMD" "$app_dir/Contents/MacOS/"
python3 scripts/package-version.py version.nfo scripts/Info.plist "$app_dir/Contents/Info.plist"
cp assets/AppIcon/LeonardoMD.icns "$app_dir/Contents/Resources/"
for resource in "$bin_dir"/*.bundle; do
  [ -e "$resource" ] || continue
  cp -R "$resource" "$app_dir/Contents/Resources/"
done
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
