# AI Usage

A native macOS menu bar app that shows remaining Claude and Codex subscription allowance and when it resets.

## Features

- Remaining allowance and reset countdowns for each reported usage window.
- Automatic detection of installed, signed-in provider tools.
- Background refresh, stale-reading indicators, and manual refresh.
- Optional low-allowance notifications and launch at login.
- Local storage with no app backend or analytics.

AI Usage tracks subscription allowance, not API spending or estimated token consumption. Claude support is experimental and requires compatible **Claude Code**; the Claude desktop app alone is insufficient. Live Claude compatibility has not yet been verified.

## Installation

Requires **macOS 14+** on Apple silicon or Intel. Install and sign in to [Codex CLI](https://developers.openai.com/codex/cli) and/or [Claude Code](https://code.claude.com/docs/en/setup) separately.

### Homebrew

```sh
brew install --cask poopsyy/tap/ai-usage
```

Open **AI Usage** from Applications. Quit it before updating with `brew update` followed by `brew upgrade --cask poopsyy/tap/ai-usage`.

### Terminal installer

```sh
curl -fsSL https://github.com/poopsyy/ai-usage-widget/releases/latest/download/install.sh | bash
```

The installer selects the native architecture, verifies the checksum and bundle signature, and installs into `~/Applications` without sudo. Open the app from Finder. Quit it and rerun the command to update. To inspect the script or select a version/location, download it first and run `bash install.sh --help`.

### Download

Download a build from [Releases](https://github.com/poopsyy/ai-usage-widget/releases): choose `macos-arm64.zip` for Apple silicon or `macos-x86_64.zip` for Intel. Download its matching `.zip.sha256`, verify it with `shasum -a 256 -c <checksum-file>`, unzip, and move **AI Usage.app** to Applications.

Use one installation method to avoid duplicate app copies. Early builds are ad-hoc signed and **not notarized by Apple**. If macOS blocks an app you trust, follow Apple's [per-app approval instructions](https://support.apple.com/en-us/102445).

### Build from source

Requires Swift 6+ and Apple's Command Line Tools (`xcode-select --install`); full Xcode is optional.

```sh
git clone https://github.com/poopsyy/ai-usage-widget.git
cd ai-usage-widget
bash scripts/build-app.sh
open "dist/AI Usage.app"
```

Move the app to its final Applications folder before enabling launch at login.

## Usage

1. Open AI Usage and click its two-bar menu bar icon. The app has no Dock icon.
2. Existing provider sign-ins are detected automatically. If needed, choose **Sign in** to use the official agent's browser login. API-key-only accounts do not provide subscription allowance.
3. Read the remaining allowance and reset countdown, or select **Refresh**. For example, a sample reading of **75% remaining · resets in 2h** means a quarter of that window's allowance has been used.
4. Configure alerts, launch at login, or a provider executable in Settings. **Pause** stops checks without signing the agent out.

**Stale** identifies older readings. **Awaiting update** means the reported reset has passed and a fresh reading is needed. If a provider is unavailable, check its official tool's sign-in and executable path in Settings.

### Removal

For an older status-line installation, first use **Restore previous status line** in Settings and restart affected Claude Code sessions. Use **Forget experimental connection** if applicable. Disable launch at login, quit, and remove the app (or run `brew uninstall --cask poopsyy/tap/ai-usage`). Data and recovery backups remain separate; see [Privacy](PRIVACY.md) before removing them.

## Tech stack

Swift, SwiftUI, AppKit, and Swift Package Manager. No third-party runtime package dependencies. Python 3 is used for development checks; see [Contributing](CONTRIBUTING.md).

## License

[MIT](LICENSE). AI Usage is independent of Anthropic and OpenAI. Provider names and logos belong to their owners; see [third-party notices](THIRD_PARTY_NOTICES.md).
