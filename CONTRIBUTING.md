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

Run `bash scripts/package-release.sh` to build the current architecture's ZIP and SHA-256 checksum under `dist/`. Version arguments must match the app's marketing version. Update the plist and provider client version together before tagging a release.

A matching `vX.Y.Z` tag triggers native Apple silicon and Intel builds and creates a **draft** release with both ZIP/checksum pairs, `install.sh`, and a pinned `ai-usage.rb`. Review the assets and release notes before publishing. Keep the ad-hoc signing and lack of notarization explicit.

The terminal installer needs a published release containing `install.sh`. To update the [Homebrew tap](https://github.com/poopsyy/homebrew-tap), add that release's generated cask as `Casks/ai-usage.rb` in the separate `poopsyy/homebrew-tap` repository. Update the cask only after publishing the matching assets. To generate it locally, supply both architecture ZIP/checksum pairs to `python3 scripts/generate-cask.py X.Y.Z dist`.

Do not commit generated app bundles, archives, or snapshots. Contributions are distributed under the project's [MIT license](LICENSE).
