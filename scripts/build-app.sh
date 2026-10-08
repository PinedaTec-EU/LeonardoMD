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
framework="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$framework" ] || { echo "Missing Sparkle framework: $framework" >&2; exit 1; }
mkdir -p "$app_dir/Contents/Frameworks"
cp -R "$framework" "$app_dir/Contents/Frameworks/"
python3 scripts/configure-update-bundle.py "$app_dir/Contents/Info.plist"
# Preserve Sparkle's vendor signatures in local builds. Distribution re-signs inside out.
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
