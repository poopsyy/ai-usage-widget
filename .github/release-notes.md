## AI Usage

A native macOS menu bar app for Claude and Codex subscription allowance.

### Installation

Requires macOS 14+. One universal ZIP runs natively on Apple silicon and Intel. Download it and its matching `.sha256`. Verify the checksum, unzip, and move **AI Usage.app** to Applications.

Or install from the terminal:

```sh
curl -fsSL https://github.com/poopsyy/ai-usage-widget/releases/latest/download/install.sh | bash
```

Or with Homebrew (the cask updates shortly after publishing):

```sh
brew tap poopsyy/ai-usage-widget https://github.com/poopsyy/ai-usage-widget
brew install --cask ai-usage
```

It verifies the download, and installs into `~/Applications` without sudo. Open the app from Finder. Quit it before rerunning the installer to update.

Provider tools are installed separately. Use signed-in Codex CLI and/or compatible Claude Code. Claude support is experimental because it reads Claude Code's `/usage` screen; the Claude desktop app alone is not enough.

### Signing and limitations

These builds are ad-hoc signed and **not notarized by Apple**. Review the [installation instructions](https://github.com/poopsyy/ai-usage-widget#installation) if macOS blocks the app. No API spending view, usage history, or automatic app updater is included.

See the [README](https://github.com/poopsyy/ai-usage-widget#readme) and [changelog](https://github.com/poopsyy/ai-usage-widget/blob/main/CHANGELOG.md) for details.
