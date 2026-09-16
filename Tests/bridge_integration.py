"""Run against the built SpiritBridge; synthetic inputs only."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest

BRIDGE = os.path.abspath(sys.argv.pop(1))


class BridgeIntegration(unittest.TestCase):
    def run_bridge(self, data, path):
        result = subprocess.run([BRIDGE, "--codex-hook", "--socket", path], input=data,
                                capture_output=True, timeout=2)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"")

    def test_bridge_binary_exists(self):
        self.assertTrue(os.path.isfile(BRIDGE), "SpiritBridge executable is missing")

    def test_real_socket_receives_only_allowlisted_event(self):
        with tempfile.TemporaryDirectory(prefix="spirit-", dir="/tmp") as directory:
            path = directory + "/events.sock"
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as receiver:
                receiver.bind(path)
                os.chmod(path, 0o600)
                receiver.settimeout(1)
                payload = {"hook_event_name": "PreToolUse", "session_id": "s", "turn_id": "t",
                           "tool_use_id": "u", "tool_name": "exec_command", "prompt": "SENSITIVE_SENTINEL",
                           "tool_input": {"command": "SENSITIVE_SENTINEL"},
                           "transcript_path": "/SENSITIVE_SENTINEL/never-open"}
                self.run_bridge(json.dumps(payload).encode(), path)
                line = receiver.recv(16384)
                self.assertEqual(line.count(b"\n"), 1)
                self.assertNotIn(b"SENSITIVE_SENTINEL", line)
                event = json.loads(line)["event"]
                self.assertEqual(event["kind"], "toolStarted")
                self.assertEqual(event["payload"]["toolCategory"], "shell")

    def test_missing_app_malformed_oversized_and_unsupported_are_silent(self):
        for data in [b"{}", b"broken", b"x" * 300000,
                     b'{"session_id":"s","hook_event_name":"Unknown"}',
                     b'{"session_id":"s","hook_event_name":"SessionStart"}']:
            self.run_bridge(data, "/tmp/build-spirit-absent-test.sock")

    def test_stalled_stdin_has_short_deadline(self):
        start = time.monotonic()
        process = subprocess.Popen([BRIDGE, "--codex-hook"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.assertEqual(process.wait(timeout=1), 0)
            self.assertLess(time.monotonic() - start, 0.9)
            self.assertEqual(process.stdout.read(), b"")
            self.assertEqual(process.stderr.read(), b"")
        finally:
            if process.poll() is None:
                process.kill()
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()


if __name__ == "__main__":
    unittest.main()
