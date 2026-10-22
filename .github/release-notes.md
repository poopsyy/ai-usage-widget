## AI Usage

A native macOS menu bar monitor for Claude Code and Codex subscription allowances.

### Installation

Requires macOS 14 or later. Download the `arm64` ZIP for Apple silicon or `x86_64` ZIP for Intel, along with its matching `.sha256` file. Verify the checksum, unzip, and move AI Usage.app to Applications.

Provider tools are installed separately. Codex reads the account signed in to the local Codex CLI. Claude requires connecting Claude Code in Settings, then sending a message in a new Claude Code Terminal session. Messages in the Claude desktop chat app do not trigger updates.

### Signing and limitations

These early builds are ad-hoc signed and **not notarized by Apple**. macOS may block a downloaded build. Review the installation guide before deciding whether to run it. There is no API spending view, usage history, or automatic app updater.

See the repository's README, installation/usage guides, and CHANGELOG for setup and version-specific details. Maintainers: add this version's changelog highlights and complete download verification before publishing this draft.
