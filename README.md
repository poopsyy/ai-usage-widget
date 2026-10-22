# AI Usage

A small macOS menu bar app that shows how much Claude and Codex subscription allowance you have left, and when it resets.

[Installation](docs/INSTALLATION.md) · [Usage guide](docs/USAGE.md) · [Troubleshooting](docs/USAGE.md#troubleshooting) · [Contributing](CONTRIBUTING.md) · [Releases](https://github.com/poopsyy/ai-usage-widget/releases)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/preview-dark.png">
  <img src="docs/images/preview-light.png" alt="AI Usage menu showing Claude and Codex allowances with sample data" width="364">
</picture>

*Preview with sample data. Your account may report different usage windows.*

> **Claude currently requires Claude Code in Terminal.** Sending a message in the Claude Mac app or on claude.ai does **not** update this widget. Desktop-only Claude monitoring is planned, not implemented.

## What it does

- Shows remaining allowance and reset countdowns for each reported usage window.
- Displays a compact `C 42% · O 54%` indicator beside the clock.
- Refreshes Codex automatically and captures Claude Code's reported limits.
- Offers optional alerts at 80% and 95% used, plus launch at login.
- Marks old readings as stale instead of presenting them as current.
- Stores snapshots on your Mac; no app backend or analytics service.

| Provider | Data source | Updates | Requirements |
| --- | --- | --- | --- |
| Codex | Local Codex app-server | Every 5 minutes, on wake, or manually | Codex CLI signed in with a ChatGPT account that reports subscription limits |
| Claude | Claude Code status-line data | During Claude Code activity; files checked every 5 seconds | Supported Claude Code version and a Pro or Max subscription |

This app tracks **subscription allowances**, not API spending, individual conversation context, or token totals. AI Usage is an independent project, unaffiliated with Anthropic or OpenAI.

## Install

You need **macOS 14 or later**. Provider tools are installed separately: [Codex CLI](https://developers.openai.com/codex/cli) and, for Claude, [Claude Code](https://code.claude.com/docs/en/setup).

### Download an app build

1. Open [Releases](https://github.com/poopsyy/ai-usage-widget/releases).
2. Choose `AI-Usage-<version>-macos-arm64.zip` for Apple silicon, or `AI-Usage-<version>-macos-x86_64.zip` for Intel. Check **Apple menu → About This Mac** if unsure.
3. Download the matching `.sha256` file and [verify the download](docs/INSTALLATION.md#verify-a-download).
4. Unzip the archive, move **AI Usage.app** to **Applications**, and open it.
5. Find `C … · O …` in the menu bar. There is no Dock icon.

If no release assets are listed yet, build from source below. GitHub's **Source code** ZIP is not a ready-to-run app.

**Early builds use ad-hoc signing and are not notarized by Apple.** macOS may block an internet-downloaded build. See [opening an early build](docs/INSTALLATION.md#opening-an-early-build) before installing. Developer ID signing and notarization are on the roadmap.

### Build from source

Install Apple's Command Line Tools if needed:

```sh
xcode-select --install
```

Check that `swift --version` reports **Swift 6 or later**, then:

```sh
git clone https://github.com/poopsyy/ai-usage-widget.git
cd ai-usage-widget
bash scripts/build-app.sh
open "dist/AI Usage.app"
```

Move the built app to Applications before enabling launch at login. See the [installation guide](docs/INSTALLATION.md) for requirements, updating, and removal.

## Connect and use

### Codex

1. Install Codex CLI using its [official instructions](https://developers.openai.com/codex/cli).
2. In Terminal, run `codex login` and sign in with your ChatGPT subscription account.
3. Open the widget and click **Refresh**.
4. If it cannot find Codex, open **Settings → Codex → Choose…** and select the `codex` executable. `command -v codex` in Terminal shows its location.

The monitored account is the one signed in to that CLI. API-key-only access does not provide the subscription reading this widget expects.

### Claude Code

1. Install [Claude Code](https://code.claude.com/docs/en/setup) and sign in to your Pro or Max account.
2. In the widget, open **Settings → Claude → Connect Claude Code**.
3. Start a **new Terminal session running `claude`** and send a message there.
4. Reopen the widget. The reading should appear shortly after Claude Code publishes its status line.

Connecting backs up your Claude user settings and wraps its status-line command, preserving existing output. To undo it, click **Restore previous status line**, then restart Claude Code.

**The Claude desktop chat app is a separate application.** A message there will not publish this integration's data. Refresh only rereads the latest Claude Code snapshot; it does not query the Claude website.

### Read the indicator

- `C` means Claude; `O` means OpenAI Codex.
- Percentages and bars show **remaining** allowance. The menu bar uses the lowest remaining percentage among fresh, unexpired windows.
- `—` means a fresh connected reading is unavailable. Open the popover for the reason.
- Readings older than 15 minutes show **Stale**.
- **Awaiting update** means the reported reset deadline has passed and a new reading is needed.

Enable **Low allowance alerts** or **Launch at login** in Settings if wanted. Both default off. Full instructions and common fixes are in the [usage guide](docs/USAGE.md).

## Privacy

App data stays in `~/Library/Application Support/AI Usage/`. The app stores current quota snapshots, alert delivery history, its Claude helper, and setup/backup metadata. It does not save Claude's complete status-line payload or manage provider credentials. Codex CLI makes its own authenticated requests to OpenAI.

Claude settings backups may contain values already present in your settings. Keep that folder private and do not attach it to issues. See [Privacy](PRIVACY.md) and [Security](SECURITY.md).

## Development

```sh
bash scripts/test.sh          # Swift checks and Python helper integration tests
bash scripts/build-app.sh debug
bash scripts/package-release.sh  # Package this Mac's architecture as a ZIP + checksum
```

There are no third-party runtime package dependencies. Python 3 is needed for the helper integration tests. Tests use temporary fixtures and do not need signed-in provider accounts.

| Guide | Purpose |
| --- | --- |
| [Contributing](CONTRIBUTING.md) | Local development, pull requests, and checks |
| [Architecture](docs/ARCHITECTURE.md) | Components, data flow, and behavior |
| [Release guide](docs/RELEASING.md) | Build, package, and publish downloads |
| [Changelog](CHANGELOG.md) | Changes prepared for release |
| [Roadmap](ROADMAP.md) | Planned work and current limitations |
| [Agent instructions](AGENTS.md) | Repository rules for coding agents |

## License

[MIT](LICENSE). Claude and Codex names belong to their respective owners.
