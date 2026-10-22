#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export CLANG_MODULE_CACHE_PATH="$root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$root/.build/ModuleCache"
swift build --disable-sandbox --cache-path "$root/.build/cache"
swift run --disable-sandbox --cache-path "$root/.build/cache" --skip-build UsageChecks
python3 -m unittest discover -s Tests -v
