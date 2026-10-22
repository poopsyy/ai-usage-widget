# Privacy

AI Usage has no app backend, analytics service, or automatic crash-report uploader. It is a local utility. This document describes the app's behavior, not the separate privacy policies of Claude, Codex, macOS, or GitHub.

## Data read

- **Codex:** quota windows, percentage used, reset timestamps, and plan information returned through the local Codex app-server.
- **Claude:** status-line JSON from Claude Code. The helper keeps only the supported usage-window percentages, reset timestamps, and observation time. The original payload is forwarded to a previously configured status-line command, if present, without being saved by AI Usage.
- **Setup:** Claude user settings are read and backed up when you click **Connect Claude Code**. The existing status-line command is preserved for forwarding and restoration.

The app does not directly read browser cookies, provider credential files, or keychains. Codex CLI uses its own sign-in and network access to retrieve usage. Provider tools may have their own logging or telemetry settings.

## Data stored

The default data folder is `~/Library/Application Support/AI Usage/`:

| File | Purpose |
| --- | --- |
| `codex.json`, `claude.json` | Latest quota snapshot; overwritten when a new reading arrives |
| `alerts.json` | Delivery keys and times used to prevent duplicate notifications |
| `claude-statusline` | Installed helper executable |
| `claude-integration.json` | Setup paths and the previous status-line configuration |
| `claude-settings-backup-*.json` | Backup of Claude user settings taken during setup |
| `claude.lock` | Coordinates concurrent snapshot writes |

Directories created by the app use private permissions. Snapshot and metadata files are written with user-only read/write permissions. macOS preferences store the chosen Codex path and alert setting; macOS manages login-item registration and notification permissions.

**Settings backups may contain private values already in your Claude settings.** They remain until you remove them. Old notification delivery keys are pruned when a new alert is recorded; there is no historical usage database.

## Sharing and deletion

Nothing is uploaded by AI Usage to a project-operated server. Notification text includes provider name and remaining allowance and may appear on your screen according to macOS notification settings.

Do not attach the data folder to GitHub issues. Send redacted screenshots or synthetic reproduction data instead.

To remove the app's data, first restore the Claude status line, restart Claude Code, disable launch at login, and quit the app. Then remove the app data folder and, if wanted, its `dev.local.ai-usage-widget` preferences. See [uninstallation](docs/INSTALLATION.md#uninstall).
