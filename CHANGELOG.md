# Changelog

## Unreleased

### Fixed

- Homebrew cask generation uses the current macOS minimum-version syntax.

## 0.1.0 - 2026-10-23

### Added

- Native menu bar display for Claude and Codex subscription allowance and reset times.
- Automatic provider discovery, official-agent sign-in, manual refresh, and pause/resume.
- Experimental Claude Code usage checks and Codex app-server integration.
- Stale-reading indicators, optional low-allowance alerts, and launch at login.
- Curl installer with verified downloads and update rollback, plus generated Homebrew casks.
- Separate Apple silicon and Intel app archives with SHA-256 checksums.

### Fixed

- Repeated Claude refreshes preserve probe metadata and wait for a recognized startup prompt.
- Recoverable provider failures preserve labeled last-known readings.

### Changed

- Concise public setup, contribution, privacy, and security instructions.
- Provider logos and consistent menu bar and app icons.
- Retired new status-line and embedded browser connections; existing restoration remains available.

### Limitations

- Claude Code integration remains experimental and has not passed live-account validation.
- Download builds are ad-hoc signed and not notarized by Apple.
- No API spending view, usage history, multi-account switching, or automatic app updater.
