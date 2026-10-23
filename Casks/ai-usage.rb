cask "ai-usage" do
  version "0.2.0"
  sha256 "dd4bacebad07a4ae1baef0d3219b9e042668045a9a7535adce9414daa9032348"

  url "https://github.com/poopsyy/ai-usage-widget/releases/download/v#{version}/AI-Usage-#{version}-macos-universal.zip"
  name "AI Usage"
  desc "Menu bar monitor for Claude and Codex subscription allowances"
  homepage "https://github.com/poopsyy/ai-usage-widget"

  depends_on macos: :sonoma

  app "AI Usage.app"

  caveats <<~EOS
    Early builds are ad-hoc signed and not notarized by Apple.
    See https://github.com/poopsyy/ai-usage-widget#installation
    Provider tools (Codex CLI and/or Claude Code) must be installed separately.
  EOS
end
