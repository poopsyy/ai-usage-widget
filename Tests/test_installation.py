"""Offline distribution checks using synthetic apps and mocked network/signing."""
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("generate_cask", ROOT / "scripts/generate-cask.py")
CASK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CASK)


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.assets = self.root / "assets"
        self.assets.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.target = self.root / "Applications with spaces"
        self.app = self.target / "AI Usage.app"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        FIXTURE_ASSETS=str(self.assets))
        self.stub("uname", 'if [[ "$1" == -s ]]; then echo Darwin; else echo "${FAKE_ARCH:-arm64}"; fi')
        self.stub("sw_vers", 'echo "${FAKE_OS:-14.0}"')
        self.stub("sysctl", 'echo "${FAKE_ARM:-0}"')
        self.stub("pgrep", 'exit "${FAKE_RUNNING:-1}"')
        self.stub("codesign", 'exit "${FAKE_SIGNATURE:-0}"')
        self.stub("curl", '''
output=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output ]]; then output="$2"; shift 2; else url="$1"; shift; fi
done
if [[ "$url" == */releases/latest ]]; then
  echo -n 'https://github.com/poopsyy/ai-usage-widget/releases/tag/v0.1.0'
else
  cp "$FIXTURE_ASSETS/${url##*/}" "$output"
fi
''')
        for arch in ("arm64", "x86_64"):
            name = f"AI-Usage-0.1.0-macos-{arch}.zip"
            with zipfile.ZipFile(self.assets / name, "w") as archive:
                archive.writestr("AI Usage.app/Contents/Info.plist", plistlib.dumps({
                    "CFBundleIdentifier": "dev.local.ai-usage-widget",
                    "CFBundleShortVersionString": "0.1.0",
                }))
                archive.writestr("AI Usage.app/Contents/Resources/architecture", arch)
            digest = hashlib.sha256((self.assets / name).read_bytes()).hexdigest()
            (self.assets / f"{name}.sha256").write_text(f"{digest}  {name}\n")

    def stub(self, name, script):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + script + "\n")
        path.chmod(0o755)

    def run_install(self, *args, success=True):
        result = subprocess.run(["bash", str(ROOT / "scripts/install.sh"),
                                 "--app-dir", str(self.target), *args],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        self.assertFalse(list(self.target.glob(".ai-usage-install.*")))
        return result

    def previous_app(self, bundle_id="dev.local.ai-usage-widget"):
        (self.app / "Contents").mkdir(parents=True)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": bundle_id}))
        (self.app / "previous").write_text("keep me")

    def test_latest_installs_native_app(self):
        self.run_install()
        self.assertEqual((self.app / "Contents/Resources/architecture").read_text(), "arm64")

    def test_explicit_version_and_intel(self):
        self.env["FAKE_ARCH"] = "x86_64"
        self.run_install("--version", "v0.1.0")
        self.assertEqual((self.app / "Contents/Resources/architecture").read_text(), "x86_64")

    def test_rosetta_selects_arm(self):
        self.env.update(FAKE_ARCH="x86_64", FAKE_ARM="1")
        self.run_install()
        self.assertEqual((self.app / "Contents/Resources/architecture").read_text(), "arm64")

    def test_bad_checksum_preserves_previous_app(self):
        self.previous_app()
        (self.assets / "AI-Usage-0.1.0-macos-arm64.zip").write_bytes(b"corrupt")
        self.run_install(success=False)
        self.assertTrue((self.app / "previous").exists())

    def test_untrusted_checksum_filename_rejected(self):
        checksum = self.assets / "AI-Usage-0.1.0-macos-arm64.zip.sha256"
        checksum.write_text("0" * 64 + "  ../../other.zip\n")
        self.run_install(success=False)
        self.assertFalse(self.app.exists())

    def test_download_failure_preserves_previous_app(self):
        self.previous_app()
        self.stub("curl", "exit 22")
        self.run_install("--version", "0.1.0", success=False)
        self.assertTrue((self.app / "previous").exists())

    def test_invalid_signature_preserves_previous_app(self):
        self.previous_app()
        self.env["FAKE_SIGNATURE"] = "1"
        self.run_install(success=False)
        self.assertTrue((self.app / "previous").exists())

    def test_existing_app_is_replaced(self):
        self.previous_app()
        self.run_install()
        self.assertFalse((self.app / "previous").exists())

    def test_failed_move_restores_previous_app(self):
        self.previous_app()
        self.stub("mv", 'if [[ "$1" == */extracted/* ]]; then exit 1; fi\nexec /bin/mv "$@"')
        self.run_install(success=False)
        self.assertTrue((self.app / "previous").exists())

    def test_unrelated_app_and_symlink_are_preserved(self):
        self.previous_app("other.app")
        self.run_install(success=False)
        self.assertTrue((self.app / "previous").exists())
        link_dir = self.root / "links"
        link_dir.mkdir()
        (link_dir / "AI Usage.app").symlink_to(self.app)
        self.run_install("--app-dir", str(link_dir), success=False)
        self.assertTrue((link_dir / "AI Usage.app").is_symlink())

    def test_requirements_and_running_app_rejected(self):
        for overrides in ({"FAKE_OS": "13.0"}, {"FAKE_ARCH": "unknown"}, {"FAKE_RUNNING": "0"}):
            with self.subTest(overrides=overrides):
                saved = self.env.copy()
                self.env.update(overrides)
                self.run_install(success=False)
                self.env = saved
        self.assertFalse(self.app.exists())

    def test_invalid_arguments_rejected(self):
        for args in (("--version", "../bad"), ("--app-dir", "relative"), ("--unknown",), ("--version",)):
            with self.subTest(args=args):
                self.run_install(*args, success=False)

    def test_cask_contains_both_verified_architectures(self):
        result = CASK.render("v0.1.0", self.assets)
        for arch in ("arm64", "x86_64"):
            digest = (self.assets / f"AI-Usage-0.1.0-macos-{arch}.zip.sha256").read_text().split()[0]
            self.assertIn(digest, result)
        self.assertIn('depends_on macos: ">= :sonoma"', result)
        self.assertIn('app "AI Usage.app"', result)

    def test_cask_refuses_missing_or_modified_assets_and_bad_version(self):
        with self.assertRaises(ValueError):
            CASK.render('bad"version', self.assets)
        archive = self.assets / "AI-Usage-0.1.0-macos-x86_64.zip"
        archive.write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            CASK.render("0.1.0", self.assets)
        archive.unlink()
        with self.assertRaises(OSError):
            CASK.render("0.1.0", self.assets)


if __name__ == "__main__":
    unittest.main()
