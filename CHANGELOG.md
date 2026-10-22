# Changelog

User-visible changes are recorded here. Entries under **Unreleased** describe repository content that has not yet been published as a release.

## Unreleased

### Added

- Native macOS menu bar UI for Claude and Codex subscription allowances.
- Codex app-server quota reads with automatic refresh and connection errors.
- Opt-in Claude Code status-line capture with settings backup and restoration.
- Remaining-allowance bars, reset countdowns, stale readings, and missing-data states.
- Optional 80% and 95% usage alerts with persistent deduplication.
- Optional launch at login and sample-data previews.
- Swift checks and compiled helper integration tests.
- Public project documentation, MIT license, issue and pull request templates.
- Native Apple silicon/Intel CI and draft release packaging with checksums.

### Known limitations

- Claude's desktop chat app and claude.ai do not trigger widget updates.
- Download builds are ad-hoc signed and are not notarized by Apple.
- No API spending, usage history, multi-account switching, or automatic app updates.
