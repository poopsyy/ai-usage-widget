cask "ai-usage" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.0"
  sha256 arm:   "2b03b4726fdc491afbf32adfca0e63524857ab9267a3a240c861d2a1d61c411e",
         intel: "03d43df17d23f029cc2356bc5b255297fce38c9524757a6db608aba8c10d84e9"

  url "https://github.com/poopsyy/ai-usage-widget/releases/download/v#{version}/AI-Usage-#{version}-macos-#{arch}.zip"
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
