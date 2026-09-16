"""Native app quota integration with an isolated, literal app-server fixture."""
import json
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest

APP = sys.argv.pop(1)


class QuotaAppIntegration(unittest.TestCase):
    def launch(self, directory, fixture):
        process = subprocess.Popen([APP, "--diagnostics", "--socket", str(directory / "events.sock"),
                                    "--quota-executable", str(fixture)], stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, text=True)
        try:
            time.sleep(2.7)
        finally:
            process.terminate()
        output, _ = process.communicate(timeout=5)
        lines = [line for line in output.splitlines() if line.startswith("BuildSpirit diagnostics: ")]
        self.assertTrue(lines, output)
        return json.loads(lines[-1].split(": ", 1)[1])

    def test_quota_maps_duration_restores_history_and_marks_failed_read(self):
        with tempfile.TemporaryDirectory(prefix="spirit-quota-") as location:
            directory = pathlib.Path(location)
            fixture = directory / "codex-fixture"
            reset = int(time.time()) + 86400 * 4
            result = {"accountId": "fixture-account", "rateLimitsByLimitId": {
                "codex": {"primary": {"usedPercent": 65, "windowDurationMins": 10080, "resetsAt": reset},
                          "secondary": None},
                "spark": {"primary": {"usedPercent": 0, "windowDurationMins": 300, "resetsAt": reset}}}}
            fixture.write_text("#!" + sys.executable + "\nimport sys,json\n"
                               "for line in sys.stdin:\n"
                               " v=json.loads(line)\n"
                               " if v.get('id')==1: print(json.dumps({'id':1,'result':{}}),flush=True)\n"
                               " if v.get('id')==2: print(json.dumps({'id':2,'result':" + repr(result) + "}),flush=True)\n")
            fixture.chmod(0o700)
            first = self.launch(directory, fixture)
            self.assertEqual(first["quotaBucketCount"], 2)
            self.assertEqual(first["quotaWeeklyRemaining"], 35)
            self.assertTrue(first["quotaHasSuccessfulRead"])
            self.assertEqual(first["quotaHistoryCount"], 1)
            archive = directory / "quota-history.json"
            self.assertEqual(archive.stat().st_mode & 0o777, 0o600)
            fixture.write_text("#!" + sys.executable + "\nimport sys,json\n"
                               "for line in sys.stdin:\n"
                               " v=json.loads(line)\n"
                               " if v.get('id')==1: print(json.dumps({'id':1,'result':{}}),flush=True)\n"
                               " if v.get('id')==2: print(json.dumps({'id':2,'error':{'code':401}}),flush=True)\n")
            second = self.launch(directory, fixture)
            self.assertEqual(second["quotaWeeklyRemaining"], 35)
            self.assertFalse(second["quotaHasSuccessfulRead"])
            self.assertEqual(second["quotaHistoryCount"], 1)


if __name__ == "__main__":
    unittest.main()
