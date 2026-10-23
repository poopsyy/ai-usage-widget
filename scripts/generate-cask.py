#!/usr/bin/env python3
"""Generate a pinned Homebrew cask from the verified universal release ZIP."""
import argparse
import hashlib
from pathlib import Path
import re


def render(version, assets):
    version = version.removeprefix("v")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Version must be X.Y.Z or vX.Y.Z")
    name = f"AI-Usage-{version}-macos-universal.zip"
    checksum = (assets / f"{name}.sha256").read_text().strip()
    match = re.fullmatch(r"([0-9a-f]{64})  " + re.escape(name), checksum)
    if not match:
        raise ValueError(f"Invalid checksum file for {name}")
    hasher = hashlib.sha256()
    with (assets / name).open("rb") as archive:
        for block in iter(lambda: archive.read(1024 * 1024), b""):
            hasher.update(block)
    digest = hasher.hexdigest()
    if digest != match[1]:
        raise ValueError(f"Checksum mismatch for {name}")
    return f'''cask "ai-usage" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/poopsyy/ai-usage-widget/releases/download/v#{{version}}/AI-Usage-#{{version}}-macos-universal.zip"
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
'''


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("assets", type=Path, help="Folder containing the universal ZIP and its checksum")
    args = parser.parse_args()
    try:
        print(render(args.version, args.assets), end="")
    except (ValueError, OSError) as error:
        parser.exit(1, f"{error}\n")
