"""Verify provider routing, three-spirit display and persisted identity in the native app."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

APP = os.path.abspath(sys.argv.pop(1))

class ProvidersIntegration(unittest.TestCase):
    def launch(self, directory, providers, hooks):
        path = directory + '/events.sock'
        if os.path.exists(path): os.unlink(path)  # Remove this fixture's refused socket before the next launch.
        process = subprocess.Popen([APP, '--diagnostics', '--socket', path, '--providers', providers],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 2
            while not os.path.exists(path) and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue(os.path.exists(path))
            bridge = os.path.join(os.path.dirname(APP), 'SpiritBridge')
            for provider, name in hooks:
                payload = {'session_id': 'shared-session', 'hook_event_name': name, 'tool_name': 'Bash'}
                if provider == 'codex': payload['turn_id'] = 'turn'
                result = subprocess.run([bridge, '--' + provider + '-hook', '--socket', path],
                                        input=json.dumps(payload).encode(), capture_output=True, timeout=2)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b'', b''))
                time.sleep(.04)
            time.sleep(2.5)
            process.terminate()
            stdout, stderr = process.communicate(timeout=5)
            lines = [line.split(b'BuildSpirit diagnostics: ', 1)[1] for line in stdout.splitlines()
                     if b'BuildSpirit diagnostics: ' in line]
            self.assertTrue(lines, stderr.decode(errors='replace'))
            return json.loads(lines[-1])
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=5)

    def test_provider_states_labels_three_limit_hidden_collection_and_restore(self):
        with tempfile.TemporaryDirectory(prefix='spirit-providers-', dir='/tmp') as directory:
            state = self.launch(directory, 'codex,claude,gemini,grok,codex', [
                ('codex', 'UserPromptSubmit'), ('claude', 'PermissionRequest'),
                ('gemini', 'BeforeAgent'), ('claude', 'Stop')])
            self.assertIn('providers', state)
            providers = {p['provider']: p for p in state['providers']}
            self.assertEqual(state['visibleProviderCount'], 3)
            self.assertEqual([p['provider'] for p in state['providers'] if p['visible']], ['codex', 'claude', 'gemini'])
            self.assertEqual(providers['codex']['state'], 'working')
            self.assertEqual(providers['claude']['state'], 'idle')
            self.assertEqual(providers['gemini']['state'], 'working')
            self.assertFalse(providers['grok']['observed'])
            for name, provider in providers.items():
                self.assertEqual(provider['label'], name.title())
                self.assertTrue(provider['visualIgnoresMouseEvents'])
                self.assertTrue(provider['interactionWithinVisual'])
            self.assertEqual(state['dashboardEventCount'], 4)
            self.assertEqual(state['dashboardWorkingCount'], 2)
            positions = [tuple(p['position']) for p in providers.values()]
            self.assertEqual(len(set(positions)), 4)
            restored = self.launch(directory, 'codex', [('claude', 'UserPromptSubmit')])
            providers = {p['provider']: p for p in restored['providers']}
            self.assertEqual(restored['visibleProviderCount'], 1)
            self.assertFalse(providers['claude']['visible'])
            self.assertEqual(providers['claude']['state'], 'working')
            self.assertEqual(providers['claude']['eventCount'], 3)
            self.assertEqual(restored['dashboardUnknownCount'], 2)
            self.assertEqual(restored['dashboardWorkingCount'], 1)

if __name__ == '__main__':
    unittest.main()
