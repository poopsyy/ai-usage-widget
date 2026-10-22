# Contributing

Thanks for helping improve AI Usage. Bugs, documentation fixes, and focused pull requests are welcome. Read the [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## Set up locally

Use a Mac with macOS 14 or later, Swift 6 or later, Apple's Command Line Tools, and Python 3. Full Xcode is optional.

```sh
git clone https://github.com/poopsyy/ai-usage-widget.git
cd ai-usage-widget
bash scripts/test.sh
bash scripts/build-app.sh debug
open "dist/AI Usage.app"
```

Fork the repository if you do not have push access, then create a branch for your change. Provider accounts are optional for development: the automated checks use fixtures.

## Make a change

- Keep provider parsing and alert logic in `UsageCore`; keep UI behavior in `AIUsage`.
- Use provider-reported quotas and reset times. Never infer subscription allowances from token counts.
- Preserve existing Claude settings and status-line output. Keep setup reversible.
- Use synthetic fixtures. Do not add account data, session payloads, credentials, absolute home paths, or live quota screenshots.
- Match the existing Swift style and keep new dependencies justified.
- Update the relevant guide and `CHANGELOG.md` when user-visible behavior changes.

For layout work, use the sample-data preview:

```sh
open -n "dist/AI Usage.app" --args --preview
```

Preview mode does not poll providers automatically. Its Settings controls are real controls: do not connect an integration or change login/notification settings during a purely visual check.

## Verify

```sh
bash scripts/test.sh
bash scripts/build-app.sh
git diff --check
```

The test script runs a standalone Swift check executable and Python tests of the compiled helper. Use this script rather than `swift test`; full XCTest is not a dependency.

Add tests for meaningful behavior changes, especially parsing, timestamps, alert delivery keys, settings preservation, and failure handling. A documentation-only change needs link and command checks rather than new runtime tests. CI builds and checks both Apple silicon and Intel targets on their native runners.

## Open a pull request

Explain the problem, resulting behavior, and checks you ran. Include sample-data screenshots for UI changes. Mention any limitations you could not verify. Keep unrelated refactors out of the same PR.

Use [issues](https://github.com/poopsyy/ai-usage-widget/issues) for reproducible bugs and feature requests. Include macOS version, CPU architecture, app version, and provider CLI version. Redact account identifiers and paths. Report security issues privately as described in [SECURITY.md](SECURITY.md).

By contributing, you agree that your contribution is distributed under the project's [MIT license](LICENSE).
