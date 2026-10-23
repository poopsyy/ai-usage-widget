# Changelog

## Unreleased

## 0.2.0 - 2026-10-24

### Added

- Optional **Faster updates during Claude Code sessions**: uses the usage Claude Code reports to its status line, with exact reset times, and falls back to the `/usage` check otherwise. It replaces **Restore previous status line**; turning it off restores your previous status line.

### Changed

- Removed **Forget experimental connection**: it deleted a Keychain item that no released version created.
- Settings and docs no longer describe Claude support as unverified; it has been checked against Claude Code 2.1.309.
- The bundle ID is now `io.github.poopsyy.ai-usage` instead of the placeholder `dev.local.ai-usage-widget`. Executable paths and pause states carry over; macOS asks for notification permission again if alerts were on, and launch at login must be turned on again.
- Homebrew installs from this repository (`brew tap poopsyy/ai-usage-widget https://github.com/poopsyy/ai-usage-widget`); the separate `poopsyy/tap` is retired.
- Releases ship one universal app for Apple silicon and Intel. The installer and Homebrew cask use it, and the installer still installs per-architecture archives of older releases.

### Fixed

- Homebrew cask generation uses the current macOS minimum-version syntax.
- Claude reset times are read from Claude Code's `/usage` labels, so Claude countdowns and low-allowance alerts work.
- Low-allowance alerts no longer repeat when a reset time is reported with slightly different precision.
- Claude checks replay terminal output incrementally instead of re-rendering the full transcript every 50 ms, greatly reducing CPU use.
- Claude checks wait briefly for the weekly row instead of saving a partial reading, and no longer mistake tips that mention `/login` for a signed-out account.
- Agent output written just before the process exits is no longer dropped.
- Connected refreshes skip the separate sign-in check, and Claude Code's option check runs once per installed version: Codex now starts one agent process per refresh and Claude three instead of five.
- Claude sign-in checks allow for slow cold starts, Codex sign-out detection no longer matches unrelated errors, and resuming during a rate-limit cooldown explains the wait.
- The app wakes every 30 seconds instead of every 5 and checks alerts only when a reading changes, reducing idle energy use.

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
