#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
  echo "Usage: scripts/build-app.sh [release|debug]" >&2
  exit 1
fi
export CLANG_MODULE_CACHE_PATH="$root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$root/.build/ModuleCache"
swift build --disable-sandbox --cache-path "$root/.build/cache" -c "$configuration"
bin_dir="$(swift build --disable-sandbox --cache-path "$root/.build/cache" -c "$configuration" --show-bin-path)"
mkdir -p "$root/dist"
staging="$(mktemp -d "$root/dist/.app-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/AI Usage.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$bin_dir/AIUsage" "$app/Contents/MacOS/AIUsage"
cp "$bin_dir/UsageBridge" "$app/Contents/Helpers/UsageBridge"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/LICENSE" "$app/Contents/Resources/LICENSE"
cp -R "$bin_dir/AIUsage_AIUsage.bundle" "$app/Contents/Resources/"
swift "$root/scripts/make-icon.swift" "$root/.build/AppIcon.iconset"
iconutil -c icns "$root/.build/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app/Contents/Helpers/UsageBridge"
codesign --force --sign - "$app"
destination="$root/dist/AI Usage.app"
# Replacing the whole bundle keeps a running instance's mapped binary intact.
if [[ -e "$destination" ]]; then mv "$destination" "$staging/Previous.app"; fi
if ! mv "$app" "$destination"; then
  if [[ -e "$staging/Previous.app" ]]; then mv "$staging/Previous.app" "$destination"; fi
  exit 1
fi
echo "Built $destination"
