# AI Usage

A small macOS menu bar app that shows how much Claude and Codex subscription allowance you have left, and when it resets.

[Installation](docs/INSTALLATION.md) · [Usage guide](docs/USAGE.md) · [Troubleshooting](docs/USAGE.md#troubleshooting) · [Contributing](CONTRIBUTING.md) · [Releases](https://github.com/poopsyy/ai-usage-widget/releases)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/preview-dark.png">
  <img src="docs/images/preview-light.png" alt="AI Usage menu showing Claude and Codex allowances with sample data" width="364">
</picture>

*Preview with sample data. Your account may report different usage windows.*

> **Claude monitoring requires installed Claude Code.** Its new automatic `/usage` probe is experimental and has passed synthetic checks, but has not yet been verified with a live account. The Claude desktop app alone is not supported.

## What it does

- Shows remaining allowance and reset countdowns for each reported usage window.
- Shows a compact two-bar icon beside the clock. Click it for usage.
- Detects installed agents and follows their existing subscription sign-ins.
- Checks quotas through short-lived agent processes; no test chat or open Terminal session is required.
- Offers official sign-in through your default browser when requested, plus pause/resume per provider.
- Offers optional alerts at 80% and 95% used, plus launch at login.
- Marks old readings as stale instead of presenting them as current.
- Stores snapshots on your Mac; no app backend or analytics service.

| Provider | Data source | Updates | Requirements |
| --- | --- | --- | --- |
| Codex | Local Codex app-server | Every 5 minutes, on wake, or manually | Codex CLI signed in with a ChatGPT account that reports subscription limits |
| Claude (experimental) | Claude Code built-in `/usage` panel | Every 5 minutes, on wake, or manually | Compatible Claude Code with `--safe-mode` and subscription quota support; live validation pending |

This app tracks **subscription allowances**, not API spending, individual conversation context, or token totals. AI Usage is an independent project, unaffiliated with Anthropic or OpenAI.

## Install

You need **macOS 14 or later**. Provider tools are installed separately: [Codex CLI](https://developers.openai.com/codex/cli) and, for Claude, [Claude Code](https://code.claude.com/docs/en/setup).

### Download an app build

1. Open [Releases](https://github.com/poopsyy/ai-usage-widget/releases).
2. Choose `AI-Usage-<version>-macos-arm64.zip` for Apple silicon, or `AI-Usage-<version>-macos-x86_64.zip` for Intel. Check **Apple menu → About This Mac** if unsure.
3. Download the matching `.sha256` file and [verify the download](docs/INSTALLATION.md#verify-a-download).
4. Unzip the archive, move **AI Usage.app** to **Applications**, and open it.
5. Find the two-bar icon in the menu bar. There is no Dock icon.

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

### Automatic agent detection

Install [Codex CLI](https://developers.openai.com/codex/cli) or [Claude Code](https://code.claude.com/docs/en/setup), then open the widget. It discovers common executable paths and the Codex desktop app's bundled executable. It follows each tool's existing login. Either provider can be used independently.

If a tool is signed out, click **Sign in** in its card or in Settings. The official agent handles authentication in your default browser (Chrome, Safari, or another browser). After login, the widget requests usage automatically. A browser session on claude.ai alone does not establish a Claude Code login. API-key-only accounts do not provide subscription allowances.

Use **Settings → Claude/Codex → Choose…** if an executable is not detected. No provider tools are installed or bundled by the widget. Claude needs a version with `auth status`, `auth login`, and safe background-probe controls; unfamiliar setup screens stop polling with guidance to finish setup in the official agent.

**Pause** stops the widget's checks, hides its reading, and suppresses its alerts without signing the agent out. **Resume** requests a fresh reading. Missing authentication never opens a browser automatically.

### Upgrading an older connection

New status-line setup and the embedded WebKit sign-in experiment have been retired. If you previously installed the status-line helper, use **Restore previous status line** in Settings and restart older Claude Code sessions. Restoration preserves unrelated settings and refuses to overwrite later edits. The helper and backups are retained for recovery.

If you used the experimental browser connection check, **Forget experimental connection** removes only the widget's saved Keychain entry. This action remains available even if the old session cannot be restored. It does not sign out Claude Code or other apps.

### Read the indicator

- Click the two-bar icon to view Claude and Codex usage.
- Percentages and bars show **remaining** allowance.
- Missing readings show a connection status instead of a percentage.
- Readings older than 15 minutes show **Stale**.
- **Awaiting update** means the reported reset deadline has passed and a new reading is needed.

Enable **Low allowance alerts** or **Launch at login** in Settings if wanted. Both default off. Full instructions and common fixes are in the [usage guide](docs/USAGE.md).

## Privacy

App data stays in `~/Library/Application Support/AI Usage/`. The app stores normalized quota snapshots and alert delivery history scoped to a hashed account/profile identity. Provider tools own authentication and network requests; the widget does not read credential files, browser cookies, or account passwords. Probe output remains in bounded memory and is never logged or saved. Provider tools may maintain their own metadata.

Claude settings backups may contain values already present in your settings. Keep that folder private and do not attach it to issues. See [Privacy](PRIVACY.md) and [Security](SECURITY.md).

## Development

```sh
bash scripts/test.sh          # Swift checks and Python helper integration tests
bash scripts/build-app.sh debug
bash scripts/package-release.sh  # Package this Mac's architecture as a ZIP + checksum
```

There are no third-party runtime package dependencies. Python 3 is needed for the helper integration tests. Tests use temporary fixtures and do not need signed-in provider accounts.

See [account connection status](docs/ACCOUNT_CONNECTIONS.md) for supported interfaces and the remaining authorized live-validation checklist. Automated checks never invoke real provider tools or send model prompts.

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
