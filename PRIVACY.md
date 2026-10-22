# Privacy

AI Usage has no app backend, analytics service, or automatic crash-report uploader. This describes the widget, not the separate policies of provider tools, browsers, macOS, or GitHub.

## Data read and authentication

- **Codex:** account identity, plan information, and subscription quota windows returned by its local app-server. No model thread or turn is created.
- **Claude:** authentication status and account/profile identifiers reported by Claude Code, plus its built-in `/usage` terminal panel. The new probe is experimental and live compatibility remains unverified. Tools, hooks, configured MCP servers, customizations, remote-control startup, prompt suggestions, and automatic updates are disabled for the probe process using supported controls. Managed provider policy still applies.
- **Legacy restoration:** existing integration metadata and the current Claude settings are read when checking/restoring an older status-line installation. Restoration changes only the status-line field and refuses to overwrite subsequent edits.

The widget does not read browser cookies, provider credential files, account passwords, or another app's Keychain entries. Explicit **Sign in** uses the official agent's browser login. The provider tool owns its callback, credential storage, refresh, and authenticated network requests. Provider tools may maintain their own logs, empty probe-session metadata, or telemetry under their own settings.

Captured terminal and JSON-RPC output stays in bounded process memory and is not logged or written to disk by the widget. Only normalized quota fields and an opaque account/profile scope are persisted. No conversation content or test chat is requested. A browser login may still require consent or reauthentication; an installed app alone does not establish a valid subscription login.

## Data stored

The default folder is `~/Library/Application Support/AI Usage/`:

| File or directory | Purpose |
| --- | --- |
| `quota-claude.json`, `quota-codex.json` | Latest normalized snapshot and hashed account/workspace/profile scope |
| `alerts-<scope>.json` | Notification delivery keys and timestamps isolated per verified account/profile |
| `ClaudeProbe/` | Private empty working directory for short-lived Claude probes |
| `codex.json`, `claude.json`, `alerts.json` | Retained legacy data; ignored by automatic monitoring |
| `claude-statusline`, `claude.lock` | Retained helper and lock for older sessions |
| `claude-integration.json` | Legacy setup metadata and previous status line |
| `claude-settings-backup-*.json` | Private backups retained for restoration |

App-created data directories use private permissions, and snapshot/metadata files use user-only read/write permissions. macOS preferences store executable paths, provider pause states, alert settings, and login-item preferences. macOS manages notification and login-item permissions.

Cached snapshots are loaded only after the official agent reports a matching account identity. Unknown identities cannot load or persist snapshots or deliver alerts. Old unscoped readings are not migrated to a guessed account. There is no historical usage database; alert keys are pruned when a successful delivery is recorded.

**Legacy settings backups can contain private values from existing Claude settings.** Preserve any backup needed for recovery and never attach the data folder to an issue.

## Retired experimental connection

The previous embedded WebKit sign-in experiment has been removed. It may have left a widget-owned Keychain item with service `dev.local.ai-usage-widget.connections`, account `claude.web.session.v1`.

**Forget experimental connection** deletes only that item without loading its contents. The action remains available after failures, and failure is never reported as successful removal. No new session item is created. Deleting Application Support alone does not remove the old item; use this action or Keychain Access.

## Pause, sharing, and deletion

Pausing stops the widget's provider checks and alerts, hides its reading, and leaves the official agent signed in. Nothing is uploaded to a project-operated server. Notification text contains provider name and remaining allowance and may appear on screen under macOS settings.

For removal, restore any legacy status line, restart older Claude Code sessions, forget an experimental connection if applicable, disable launch at login, and quit. Then delete the app/data folder and optionally its `dev.local.ai-usage-widget` preferences. Removing the widget does not remove provider tools or sign them out. See [uninstallation](docs/INSTALLATION.md#uninstall).
