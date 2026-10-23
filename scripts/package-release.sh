#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
requested="${1:-$version}"
requested="${requested#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || "$requested" != "$version" ]]; then
  echo "Version must match Info.plist ($version), using major.minor.patch." >&2
  exit 1
fi
bash scripts/build-app.sh release
codesign --verify --deep --strict "dist/AI Usage.app"
asset="AI-Usage-${version}-macos-universal.zip"
temporary="$(mktemp -d "$root/dist/.release.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
ditto -c -k --sequesterRsrc --keepParent "dist/AI Usage.app" "$temporary/$asset"
mv "$temporary/$asset" "dist/$asset"
(cd dist && shasum -a 256 "$asset" > "$asset.sha256")
echo "Packaged dist/$asset"
echo "Checksum dist/$asset.sha256"
