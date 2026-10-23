# Privacy

AI Usage has no app backend, analytics service, or automatic crash-report uploader. This describes the widget, not the separate policies of provider tools, browsers, macOS, or GitHub.

## Data read and authentication

- **Codex:** account identity, plan information, and subscription quota windows returned by its local app-server. No model thread or turn is created.
- **Claude:** authentication status and account/profile identifiers reported by Claude Code, plus its built-in `/usage` terminal panel. The new probe is experimental and live compatibility remains unverified. Tools, hooks, configured MCP servers, customizations, remote-control startup, prompt suggestions, and automatic updates are disabled for the probe process using supported controls. Managed provider policy still applies.
- **Faster Claude updates (optional, off by default):** turning this on adds a status-line command to Claude Code's `settings.json` (backing up the file first) and chains any status line you already had. Claude Code then passes its status-line data to the widget's helper, which saves only the reported quota windows. Turning it off changes only the status-line field back and refuses to overwrite later edits. A captured reading is used only after the account it would be shown for has been verified, and a full `/usage` check still runs at least every 30 minutes.

The widget does not read browser cookies, provider credential files, account passwords, or another app's Keychain entries. Explicit **Sign in** uses the official agent's browser login. The provider tool owns its callback, credential storage, refresh, and authenticated network requests. Provider tools may maintain their own logs, empty probe-session metadata, or telemetry under their own settings.

Captured terminal and JSON-RPC output stays in bounded process memory and is not logged or written to disk by the widget. Only normalized quota fields and an opaque account/profile scope are persisted. No conversation content or test chat is requested. A browser login may still require consent or reauthentication; an installed app alone does not establish a valid subscription login.

## Data stored

The default folder is `~/Library/Application Support/AI Usage/`:

| File or directory | Purpose |
| --- | --- |
| `quota-claude.json`, `quota-codex.json` | Latest normalized snapshot and hashed account/workspace/profile scope |
| `alerts-<scope>.json` | Notification delivery keys and timestamps isolated per verified account/profile |
| `ClaudeProbe/` | Private working directory for short-lived Claude probes; provider-created metadata may remain |
| `claude-probe.json` | Latest Claude `/usage` reading and hashed scope, used to validate status-line readings |
| `claude-scope.json` | Hashed scope and the time it was first seen, so earlier status-line readings are never attributed to it |
| `claude.json`, `claude.lock` | Latest status-line quota reading and its lock |
| `claude-statusline` | Status-line helper copy called by Claude Code sessions; kept current after app updates |
| `claude-integration.json` | Status-line setup metadata and the previous status line |
| `claude-settings-backup-*.json` | Private backups retained for restoration |
| `codex.json`, `alerts.json` | Retained legacy data; ignored by automatic monitoring |

App-created data directories use private permissions, and snapshot/metadata files use user-only read/write permissions. macOS preferences store executable paths, provider pause states, alert settings, and login-item preferences. macOS manages notification and login-item permissions.

Cached snapshots are loaded only after the official agent reports a matching account identity. Unknown identities cannot load or persist snapshots or deliver alerts. Old unscoped readings are not migrated to a guessed account. There is no historical usage database; alert keys are pruned when a successful delivery is recorded.

**Settings backups can contain private values from existing Claude settings.** Preserve any backup needed for recovery and never attach the data folder to an issue.

## Retired experimental connection

The previous embedded WebKit sign-in experiment has been removed. It may have left a widget-owned Keychain item with service `dev.local.ai-usage-widget.connections`, account `claude.web.session.v1`.

**Forget experimental connection** deletes only that item without loading its contents. The action remains available after failures, and failure is never reported as successful removal. No new session item is created. Deleting Application Support alone does not remove the old item; use this action or Keychain Access.

## Pause, sharing, and deletion

Pausing stops the widget's provider checks and alerts, hides its reading, and leaves the official agent signed in. Nothing is uploaded to a project-operated server. Notification text contains provider name and remaining allowance and may appear on screen under macOS settings.

For removal, turn off faster Claude updates (restoring your previous status line), restart older Claude Code sessions, forget an experimental connection if applicable, disable launch at login, and quit. Then delete the app/data folder and optionally its `dev.local.ai-usage-widget` preferences. Removing the widget does not remove provider tools or sign them out. See [removal instructions](README.md#removal).
