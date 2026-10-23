"""Exercise the compiled helper with real stdin, stdout and concurrent processes."""
import base64
import concurrent.futures
import json
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / ".build/debug/UsageBridge"


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ai usage '")
        self.directory = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def payload(self, percent=42):
        return json.dumps({
            "rate_limits": {
                "five_hour": {"used_percentage": percent, "resets_at": 1900000000},
                "seven_day": {"used_percentage": 21, "resets_at": 1900600000},
            },
            "session_id": "PRIVATE-SESSION",
            "workspace": {"current_dir": "/PRIVATE-WORKSPACE"},
        }).encode()

    def run_bridge(self, payload):
        return subprocess.run([str(BRIDGE), "--directory", str(self.directory)],
                              input=payload, capture_output=True, timeout=8, check=True)

    def test_actual_helper_persists_only_allowances(self):
        result = self.run_bridge(self.payload())
        self.assertIn(b"42% used", result.stdout)
        raw = (self.directory / "claude.json").read_text()
        snapshot = json.loads(raw)
        self.assertEqual(snapshot["provider"], "claude")
        self.assertEqual(snapshot["windows"][0]["usedPercent"], 42)
        self.assertNotIn("PRIVATE", raw)
        self.assertEqual(result.stderr, b"")

    def test_session_title_and_sonnet_window(self):
        payload = json.loads(self.payload())
        payload["rate_limits"]["seven_day_sonnet"] = {"used_percentage": 7, "resets_at": 1900600000}
        result = self.run_bridge(json.dumps(payload).encode())
        self.assertIn(b"Session: 42% used", result.stdout)
        windows = json.loads((self.directory / "claude.json").read_text())["windows"]
        self.assertEqual([w["id"] for w in windows], ["five_hour", "seven_day", "seven_day_sonnet"])

    def test_absent_or_malformed_data_retains_last_snapshot(self):
        self.run_bridge(self.payload())
        before = (self.directory / "claude.json").read_bytes()
        for payload in [b"{}", b"invalid json", b'{"rate_limits":null}']:
            self.run_bridge(payload)
            self.assertEqual((self.directory / "claude.json").read_bytes(), before)

    def test_existing_status_line_receives_original_stdin(self):
        script = self.directory / "old status.py"
        script.write_text("import json,sys\np=json.load(sys.stdin)\nprint('original:'+p['session_id'])\n")
        previous = {"type": "command", "command": "/usr/bin/python3 " + shlex.quote(str(script))}
        state = {
            "settingsURL": (self.directory / "settings.json").as_uri(),
            "previousStatusLine": base64.b64encode(json.dumps(previous).encode()).decode(),
            "installedCommand": "unused",
            "backupURL": (self.directory / "backup.json").as_uri(),
        }
        (self.directory / "claude-integration.json").write_text(json.dumps(state))
        result = self.run_bridge(self.payload())
        self.assertEqual(result.stdout, b"original:PRIVATE-SESSION\n")
        self.assertTrue((self.directory / "claude.json").exists())

    def test_concurrent_sessions_write_complete_snapshots(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
            results = list(executor.map(self.run_bridge, [self.payload(i) for i in range(12)]))
        self.assertEqual(len(results), 12)
        snapshot = json.loads((self.directory / "claude.json").read_text())
        self.assertEqual(len(snapshot["windows"]), 2)
        self.assertIn(snapshot["windows"][0]["usedPercent"], range(12))


if __name__ == "__main__":
    unittest.main()
