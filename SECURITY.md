# Security

## Report a vulnerability

Do not post credentials, provider settings, private account data, or exploit details publicly. Use **Security → Report a vulnerability** on the [repository](https://github.com/poopsyy/ai-usage-widget/security) when available. Otherwise, open an issue requesting a private reporting channel without sensitive details.

Include the affected version, impact, and reproduction steps using synthetic data. Security fixes target the latest release and the current `main` branch.

## Trust boundaries

- Installed provider tools manage authentication and authenticated quota requests. The widget does not read credential files or import browser sessions.
- Selecting a custom provider executable means trusting that executable. The experimental Claude probe requires supported safe-probe controls.
- Legacy status-line restoration reads the widget's integration metadata and current Claude settings. It preserves unrelated settings and refuses to overwrite later edits. New status-line installation is retired.
- Local settings backups may contain private values. Keep them private and preserve any needed for restoration.
- Early builds are ad-hoc signed and not notarized. SHA-256 verifies download integrity; an ad-hoc signature does not establish an Apple Developer ID.

Contributions must use synthetic data and keep workflow credentials scoped to the job that needs them. Never run untrusted pull-request code with repository secrets.
