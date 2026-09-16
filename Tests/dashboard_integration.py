"""Exercise the native app's isolated hook -> SQLite -> dashboard path."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest

APP = os.path.abspath(sys.argv.pop(1))


class DashboardIntegration(unittest.TestCase):
    def run_app(self, path, payloads):
        process = subprocess.Popen([APP, "--diagnostics", "--socket", path],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 2
            while not os.path.exists(path) and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(os.path.exists(path))
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sender:
                for payload in payloads:
                    sender.sendto(json.dumps({"event": payload}).encode() + b"\n", path)
                    time.sleep(0.02)
            time.sleep(2.6)
            process.terminate()
            stdout, stderr = process.communicate(timeout=3)
            lines = [line.split(b"BuildSpirit diagnostics: ", 1)[1] for line in stdout.splitlines()
                     if b"BuildSpirit diagnostics: " in line]
            self.assertTrue(lines, stderr.decode(errors="replace"))
            return json.loads(lines[-1])
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=3)

    def test_deduplicates_persists_and_marks_restored_work_unknown(self):
        now = time.time() - 978307200  # Foundation Date's JSON epoch.
        base = dict(schemaVersion=1, provider="codex", sessionID="dashboard-fixture",
                    turnID="turn", occurredAt=now, receivedAt=now,
                    source="codex.command-hook", sourceVersion="fixture", payload={})
        start = dict(base, eventID="start", kind="turnStarted")
        tool = dict(base, eventID="tool", kind="toolStarted", payload={"toolCategory": "shell"})
        # Extra unallowlisted fields must not enter the stored JSON.
        tool["payload"]["command"] = "SENSITIVE_SENTINEL"
        with tempfile.TemporaryDirectory(prefix="spirit-dash-", dir="/tmp") as directory:
            path = directory + "/events.sock"
            first = self.run_app(path, [start, tool, tool])
            self.assertEqual(first.get("dashboardEventCount"), 2)
            self.assertEqual(first.get("dashboardToolCount"), 1)
            self.assertEqual(first.get("dashboardWorkingCount"), 1)
            second = self.run_app(path, [])
            self.assertEqual(second.get("dashboardEventCount"), 2)
            self.assertEqual(second.get("dashboardUnknownCount"), 1)
            self.assertEqual(second.get("dashboardWorkingCount"), 0)
            for filename in os.listdir(directory):
                if ".sqlite" in filename:
                    with open(directory + "/" + filename, "rb") as file:
                        self.assertNotIn(b"SENSITIVE_SENTINEL", file.read())


if __name__ == "__main__":
    unittest.main()
