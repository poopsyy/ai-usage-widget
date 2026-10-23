# Contributing

Focused bug fixes, documentation improvements, and pull requests are welcome. Follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report vulnerabilities using [Security](SECURITY.md).

## Development

Use macOS 14+, Swift 6+, Apple's Command Line Tools, and Python 3. Full Xcode is optional.

```sh
git clone https://github.com/poopsyy/ai-usage-widget.git
cd ai-usage-widget
bash scripts/test.sh
bash scripts/build-app.sh debug
open -n "dist/AI Usage.app" --args --preview
```

Preview mode uses labeled synthetic data and disables provider polling and Settings changes. Automated tests use fake provider executables and need no signed-in accounts. Use `scripts/test.sh` rather than `swift test`.

## Changes and validation

- Keep provider logic in `UsageCore` and AppKit/SwiftUI presentation in `AIUsage`.
- Preserve reported quota windows, unknown fields, stale states, existing settings, and restoration safeguards.
- Use synthetic fixtures. Never commit credentials, account payloads, personal paths, settings backups, or live account screenshots.
- Add meaningful tests for behavior changes and update public instructions and the changelog as needed.

Before submitting:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
git diff --check
```

Describe the problem, resulting behavior, and checks performed in the pull request. Keep changes focused. Report bugs and feature requests through [Issues](https://github.com/poopsyy/ai-usage-widget/issues), with versions and reproduction steps that exclude private data.

## Release packaging

Run `bash scripts/package-release.sh` to build the universal (arm64 + x86_64) ZIP and SHA-256 checksum under `dist/`; Command Line Tools are enough. `bash scripts/build-app.sh debug` builds a faster native-only app. Version arguments must match the app's marketing version. The Codex client version is read from the app bundle.

A matching `vX.Y.Z` tag runs the checks on Apple silicon and Intel, packages one universal app, and creates a **draft** release with its ZIP/checksum pair, `install.sh`, and a pinned `ai-usage.rb`. Review the assets and release notes before publishing. Keep the ad-hoc signing and lack of notarization explicit.

The terminal installer needs a published release containing `install.sh`. This repository is also the Homebrew tap: publishing a release runs `.github/workflows/cask.yml`, which regenerates `Casks/ai-usage.rb` from the published archive and commits it to `main`. Don't edit the cask by hand; to preview it, supply the universal ZIP/checksum pair to `python3 scripts/generate-cask.py X.Y.Z dist`.

Bump `CFBundleShortVersionString` in `Resources/Info.plist` for each release; the build number is set from it automatically.

Do not commit generated app bundles, archives, or snapshots. Contributions are distributed under the project's [MIT license](LICENSE).
