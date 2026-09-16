"""Verify the built app/embedded bridge/reducer/character path with an isolated socket."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

APP = os.path.abspath(sys.argv.pop(1))


class AppHookIntegration(unittest.TestCase):
    def test_embedded_bridge_drives_character_attention(self):
        self.assert_character_state([{"session_id": "integration", "turn_id": "t",
                                      "hook_event_name": "PermissionRequest", "tool_name": "Bash"}], "attention")

    def test_session_end_returns_to_idle_without_another_hook(self):
        self.assert_character_state([{"session_id": "ended", "hook_event_name": "SessionEnd"}], "idle")

    def test_completion_timeout_preserves_new_working_and_attention(self):
        for name, expected in [("UserPromptSubmit", "working"), ("PermissionRequest", "attention")]:
            with self.subTest(event=name):
                self.assert_character_state([
                    {"session_id": "ended", "hook_event_name": "SessionEnd"},
                    {"session_id": "active", "turn_id": "t", "hook_event_name": name, "tool_name": "Bash"}
                ], expected)

    def assert_character_state(self, payloads, expected):
        bridge = os.path.join(os.path.dirname(APP), "SpiritBridge")
        self.assertTrue(os.path.isfile(bridge), "App does not bundle SpiritBridge")
        with tempfile.TemporaryDirectory(prefix="spirit-app-", dir="/tmp") as directory:
            path = directory + "/events.sock"
            process = subprocess.Popen([APP, "--diagnostics", "--socket", path],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 1.5
                while not os.path.exists(path) and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(os.path.exists(path), "App listener was not started")
                for payload in payloads:
                    sent = subprocess.run([bridge, "--codex-hook", "--socket", path],
                                          input=json.dumps(payload).encode(), capture_output=True, timeout=2)
                    self.assertEqual((sent.returncode, sent.stdout, sent.stderr), (0, b"", b""))
                    time.sleep(0.05)
                time.sleep(2.5)
                process.terminate()
                stdout, stderr = process.communicate(timeout=3)
                lines = [line.split(b"BuildSpirit diagnostics: ", 1)[1]
                         for line in stdout.splitlines() if b"BuildSpirit diagnostics: " in line]
                self.assertTrue(lines, stderr.decode(errors="replace"))
                state = json.loads(lines[-1])
                self.assertEqual(state["state"], expected)
                self.assertTrue(state["hookSocketListening"])
                self.assertEqual(state["hookSessionCount"], len({p["session_id"] for p in payloads}))
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.communicate(timeout=3)


if __name__ == "__main__":
    unittest.main()
