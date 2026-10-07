#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
app_dir="$PWD/output/LeonardoMD.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/LeonardoMD" "$app_dir/Contents/MacOS/"
cp scripts/Info.plist "$app_dir/Contents/Info.plist"
cp assets/AppIcon/LeonardoMD.icns "$app_dir/Contents/Resources/"
for resource in "$bin_dir"/*.bundle; do
  [ -e "$resource" ] || continue
  cp -R "$resource" "$app_dir/Contents/Resources/"
done
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
