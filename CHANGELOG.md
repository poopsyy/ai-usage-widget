# Changelog

User-visible changes are recorded here. Entries under **Unreleased** describe repository content that has not yet been published as a release.

## Unreleased

### Changed

- Matching app, widget, and menu bar icons, with clearer provider and action symbols.
- Menu bar shows only the two-bar icon; usage appears in the popover.
- Shorter labels, settings, and connection messages. Claude's experimental status stays visible.

### Added

- Automatic installed-agent discovery and short-lived subscription quota checks; existing sign-ins require no widget connection step.
- Explicit official-agent sign-in using the default browser, plus per-provider pause/resume without signing the agent out.
- Experimental Claude Code `/usage` probe with bounded terminal parsing and no test chat. Live compatibility remains unverified.
- Verified account/profile-scoped snapshots and alert ledgers; legacy unscoped readings are not reused.
- Retirement of embedded WebKit sign-in and new status-line setup; legacy restoration and retryable deletion of the widget's experimental Keychain item remain available.
- Synthetic process tests covering browser login, account isolation, cancellation, cooldowns, and migration cleanup.
- Native macOS menu bar UI for Claude and Codex subscription allowances.
- Codex app-server quota reads with automatic refresh and connection errors.
- Legacy Claude Code status-line helper and protected restoration for existing installations.
- Remaining-allowance bars, reset countdowns, stale readings, and missing-data states.
- Optional 80% and 95% usage alerts with persistent deduplication.
- Optional launch at login and sample-data previews.
- Swift checks and compiled helper integration tests.
- Public project documentation, MIT license, issue and pull request templates.
- Native Apple silicon/Intel CI and draft release packaging with checksums.

### Known limitations

- Claude's automatic probe requires compatible installed Claude Code and has not passed live-account validation. Desktop-only Claude is not supported.
- Ambiguous terminal reset labels remain unknown; those windows cannot trigger reset-scoped alerts.
- Download builds are ad-hoc signed and are not notarized by Apple.
- No API spending, usage history, multi-account switching, or automatic app updates.
