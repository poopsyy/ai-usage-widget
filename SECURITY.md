# Security

## Reporting a vulnerability

Do not post credentials, settings backups, private usage data, or exploit details in a public issue.

Use **Security → Report a vulnerability** on the [repository](https://github.com/poopsyy/ai-usage-widget/security) if private reporting is enabled. Otherwise, open an issue requesting a private contact channel without including the vulnerability details. A response-time guarantee is not currently offered.

Include the affected version, reproduction steps using synthetic data, expected impact, and a suggested fix if available.

## Supported versions

Security fixes target the latest released version and the current `main` branch. Earlier releases do not have a separate maintenance policy. Until the first release is published, `main` is the supported development version.

## Trust boundaries

- Provider credentials remain managed by installed provider tools. AI Usage does not require API keys or collect login tokens.
- Codex is a local child process that performs authenticated quota reads. Choosing a custom executable means trusting that executable.
- Connecting Claude installs a helper and changes the user's Claude status-line command after saving a private backup. An existing status-line command is executed to preserve its output.
- The data folder and settings backups belong to the local user. Backups may contain secrets already present in Claude settings.
- Early app builds are ad-hoc signed, not Developer ID signed or notarized. Download only from releases you trust and compare the published checksum. A checksum is an integrity check, not an Apple notarization.

## Before publishing changes

Use synthetic fixtures and sample-data screenshots. Review staged files for personal paths, credentials, and provider payloads. Never commit `.claude`, `.codex`, app snapshots, keychains, or settings backups. Keep workflow token permissions limited to the job that needs them. Do not run code from forked pull requests with repository secrets.
