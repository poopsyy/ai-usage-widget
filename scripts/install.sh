#!/bin/bash
# Standalone macOS installer. Requires only tools shipped with macOS.
set -euo pipefail

fail() { echo "AI Usage: $*" >&2; exit 1; }
version=""
app_dir="$HOME/Applications"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|--app-dir)
      [[ $# -ge 2 && -n "$2" ]] || fail "Missing value for $1."
      if [[ "$1" == --version ]]; then version="${2#v}"; else app_dir="$2"; fi
      shift 2 ;;
    --help|-h)
      echo 'Usage: bash install.sh [--version X.Y.Z] [--app-dir /Applications]'
      echo 'Defaults: latest stable release, installed in ~/Applications. Quit the app before updating.'
      exit 0 ;;
    *) fail "Unknown option: $1. Use --help." ;;
  esac
done
[[ -z "$version" || "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Version must be X.Y.Z.'
[[ "$app_dir" == /* ]] || fail '--app-dir must be an absolute path.'
[[ "$(uname -s)" == Darwin ]] || fail 'macOS 14 or later is required.'
os_version="$(sw_vers -productVersion)"
[[ "${os_version%%.*}" -ge 14 ]] || fail 'macOS 14 or later is required.'
architecture="$(uname -m)"
# Prefer the native build even when Terminal is running under Rosetta.
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then architecture=arm64; fi
case "$architecture" in arm64|x86_64) ;; *) fail "Unsupported architecture: $architecture." ;; esac
if pgrep -x AIUsage >/dev/null; then fail 'Quit AI Usage before installing or updating.'; fi

repository='https://github.com/poopsyy/ai-usage-widget'
download() {
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 300 --retry 2 "$@"
}
if [[ -z "$version" ]]; then
  latest="$(download --output /dev/null --write-out '%{url_effective}' "$repository/releases/latest")" \
    || fail 'Cannot find a published release. Check the Releases page or use --version X.Y.Z.'
  [[ "$latest" == "$repository/releases/tag/v"* ]] || fail 'No supported stable release found.'
  version="${latest##*/v}"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Release tag must be vX.Y.Z.'
fi

mkdir -p "$app_dir"
destination="$app_dir/AI Usage.app"
[[ ! -L "$destination" ]] || fail 'Destination is a symlink; remove it manually first.'
if [[ -e "$destination" ]]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$existing_id" == dev.local.ai-usage-widget ]] || fail 'Destination is not a recognized AI Usage app.'
fi
staging="$(mktemp -d "$app_dir/.ai-usage-install.XXXXXX")"
cleanup() {
  # Restore the previous app if replacement failed after moving it aside.
  if [[ -e "$staging/Previous.app" && ! -e "$destination" ]]; then
    mv "$staging/Previous.app" "$destination" || {
      echo "Previous app retained at $staging/Previous.app" >&2
      return
    }
  fi
  rm -rf "$staging"
}
trap cleanup EXIT
asset="AI-Usage-${version}-macos-${architecture}.zip"
echo "Downloading AI Usage $version ($architecture)…"
download --output "$staging/$asset" "$repository/releases/download/v$version/$asset"
download --output "$staging/$asset.sha256" "$repository/releases/download/v$version/$asset.sha256"
# Parse exactly one digest and the expected filename; never trust checksum paths.
checksum="$(cat "$staging/$asset.sha256")"
expected="${checksum%% *}"
[[ "$expected" =~ ^[[:xdigit:]]{64}$ && "$checksum" == "$expected  $asset" ]] \
  || fail 'Invalid checksum file.'
actual="$(shasum -a 256 "$staging/$asset")"
[[ "${actual%% *}" == "$expected" ]] || fail 'Download checksum mismatch; app was not installed.'
ditto -x -k "$staging/$asset" "$staging/extracted"
app="$staging/extracted/AI Usage.app"
[[ -d "$app" && ! -L "$app" ]] || fail 'Archive is missing AI Usage.app.'
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$bundle_id" == dev.local.ai-usage-widget && "$bundle_version" == "$version" ]] \
  || fail 'Downloaded app identity or version does not match the release.'
codesign --verify --deep --strict "$app"
# Check again in case the user launched the app while the download was running.
if pgrep -x AIUsage >/dev/null; then fail 'Quit AI Usage and run the installer again.'; fi
if [[ -e "$destination" ]]; then mv "$destination" "$staging/Previous.app"; fi
mv "$app" "$destination"
echo "Installed $destination"
echo "Open it from Finder. Download builds are ad-hoc signed and not notarized by Apple."
echo "If macOS blocks it, review System Settings → Privacy & Security → Open Anyway."
echo 'Provider tools are installed separately. Setup: https://github.com/poopsyy/ai-usage-widget#installation'
