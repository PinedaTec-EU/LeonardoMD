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
cp "$bin_dir/LeonardoSyncHelper" "$app_dir/Contents/MacOS/"
mkdir -p "$app_dir/Contents/Library/LaunchAgents"
cp scripts/eu.pinedatec.LeonardoMD.sync-helper.plist "$app_dir/Contents/Library/LaunchAgents/"
codesign --force --sign - --identifier eu.pinedatec.LeonardoMD.sync-helper "$app_dir/Contents/MacOS/LeonardoSyncHelper"
python3 scripts/package-version.py version.nfo scripts/Info.plist "$app_dir/Contents/Info.plist"
python3 scripts/package-release-changes.py deploy/release-changes.json version.nfo "$app_dir/Contents/Resources/ReleaseChanges.json"
preview="$app_dir/Contents/Resources/LeonardoPreview"
mkdir -p "$preview/scripts" "$preview/references"
cp plugins/leonardo-format/skills/leonardo-format/scripts/*.py "$preview/scripts/"
cp plugins/leonardo-format/skills/leonardo-format/references/mdlf-v*.schema.json "$preview/references/"
python3 plugins/leonardo-format/package-renderer.py --output "$preview/references/renderer.zip"
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
python3 scripts/qa-bundle.py --verify-only "$app_dir"
printf '%s\n' "$app_dir"
