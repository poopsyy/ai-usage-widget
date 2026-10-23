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
build() { swift build --disable-sandbox --cache-path "$root/.build/cache" -c "$configuration" "$@"; }
mkdir -p "$root/dist"
staging="$(mktemp -d "$root/dist/.app-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/AI Usage.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
if [[ "$configuration" == release ]]; then
  # One universal app for Apple silicon and Intel. Per-triple builds work with Command Line Tools alone.
  slices=()
  for architecture in arm64 x86_64; do
    build --triple "$architecture-apple-macosx14.0"
    slices+=("$(build --triple "$architecture-apple-macosx14.0" --show-bin-path)")
  done
  bin_dir="${slices[0]}"
  for product in AIUsage UsageBridge; do
    lipo -create "${slices[0]}/$product" "${slices[1]}/$product" -output "$staging/$product"
    for architecture in arm64 x86_64; do
      lipo "$staging/$product" -verify_arch "$architecture" || { echo "$product is missing $architecture" >&2; exit 1; }
    done
  done
  mv "$staging/AIUsage" "$app/Contents/MacOS/AIUsage"
  mv "$staging/UsageBridge" "$app/Contents/Helpers/UsageBridge"
else
  build
  bin_dir="$(build --show-bin-path)"
  cp "$bin_dir/AIUsage" "$app/Contents/MacOS/AIUsage"
  cp "$bin_dir/UsageBridge" "$app/Contents/Helpers/UsageBridge"
fi
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
