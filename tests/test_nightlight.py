import array
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('nightlight', Path(__file__).resolve().parents[1] / 'bin/monitor-nightlight.py')
nl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nl)


class FakeDisplay:
    manager = 3
    def __init__(self):
        self.outputs = {4: {'name': 'DP-1', 'temperature': None, 'error': ''},
                        5: {'name': 'DP-2', 'temperature': None, 'error': ''}}
        self.calls = []
        self.fail = False
    def apply(self, output, temperature):
        if self.fail:
            raise RuntimeError('Gamma control denied')
        self.calls.append((output, temperature))
        self.outputs[output]['temperature'] = temperature


class NightLightTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='monitor-nightlight-test-')
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.config = self.home / '.config/monitor-switcher/config.json'
        self.config.parent.mkdir(parents=True)
        self.monitors = [{'output': 'DP-1', 'identity': {'make': 'Test', 'model': 'Main', 'serial': '123'}}, {'output': 'DP-2'}]
        self.config.write_text(json.dumps(self.monitors))
        self.display = FakeDisplay()
        self.service = nl.NightLight(self.home, self.display)
        self.service.load_monitors()

    def test_changes_only_selected_output_and_off_restores_it(self):
        self.service.command({'output': 'DP-2', 'value': '4000'})
        self.assertEqual(self.display.calls, [(5, 4000)])
        self.assertIsNone(self.display.outputs[4]['temperature'])
        self.service.command({'output': 'DP-2', 'value': 'off'})
        self.assertEqual(self.display.calls[-1], (5, None))
        self.assertFalse(json.loads(self.service.path.read_text())['output:DP-2']['enabled'])

    def test_identical_monitor_identities_still_have_independent_preferences(self):
        self.monitors[1]['identity'] = self.monitors[0]['identity']
        self.config.write_text(json.dumps(self.monitors))
        self.service.load_monitors()
        self.service.command({'output': 'DP-1', 'value': '3500'})
        self.service.reconcile()
        self.assertEqual(self.display.calls, [(4, 3500)])
        self.assertIsNone(self.display.outputs[5]['temperature'])
        self.assertEqual(self.service.preference('DP-1')[0], 'output:DP-1')

    def test_temperature_survives_restart_and_connector_change(self):
        self.service.command({'output': 'DP-1', 'value': '3500'})
        self.monitors[0]['output'] = 'DP-4'
        self.config.write_text(json.dumps(self.monitors))
        self.display.outputs[4].update(name='DP-4', temperature=None)
        restored = nl.NightLight(self.home, self.display)
        restored.reconcile()
        self.assertEqual(self.display.calls[-1], (4, 3500))
        self.assertIsNone(self.display.outputs[5]['temperature'])

    def test_new_hotplug_output_reapplies_only_its_saved_warmth(self):
        self.service.command({'output': 'DP-2', 'value': '2500'})
        del self.display.outputs[5]
        self.service.reconcile()
        self.display.outputs[6] = {'name': 'DP-2', 'temperature': None, 'error': ''}
        self.service.reconcile()
        self.assertEqual(self.display.calls[-1], (6, 2500))

    def test_rejected_gamma_does_not_persist_success(self):
        self.display.fail = True
        with self.assertRaises(RuntimeError):
            self.service.command({'output': 'DP-1', 'value': '4000'})
        self.assertFalse(self.service.path.exists())
        self.assertEqual(self.service.preferences, {})

    def test_failed_save_restores_previous_color(self):
        with patch.object(nl, 'write_json', side_effect=OSError('disk full')):
            with self.assertRaises(OSError):
                self.service.command({'output': 'DP-1', 'value': '4000'})
        self.assertEqual(self.display.calls, [(4, 4000), (4, None)])
        self.assertEqual(self.service.preferences, {})

    def test_invalid_requests_do_not_change_displays(self):
        for request in [{'output': 'MISSING', 'value': '4000'}, {'output': 'DP-1', 'value': '100'},
                        {'output': 'DP-1', 'value': '7000'}, {'output': 'DP-1', 'value': '4000;bad'}]:
            with self.assertRaises((ValueError, TypeError)):
                self.service.command(request)
        self.assertEqual(self.display.calls, [])

    def test_transient_compositor_stall_latches_error_without_killing_reconcile(self):
        # socket.timeout is an OSError: a stalled compositor reply must latch a
        # per-display error, not propagate out of reconcile and kill the service.
        import io, contextlib
        self.service.command({'output': 'DP-1', 'value': '4000'})
        def stall(output, temperature):
            raise TimeoutError('timed out')
        self.display.apply = stall
        self.display.outputs[4]['temperature'] = None  # force a re-apply attempt
        self.service.reconcile()  # must not raise
        self.assertIn('timed out', self.display.outputs[4]['error'])
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.service.publish(force=True)
        self.assertIn('timed out', out.getvalue())

    def test_corrupt_monitor_config_is_reported_without_killing_the_service(self):
        self.service.command({'output': 'DP-1', 'value': '4000'})
        calls = list(self.display.calls)
        self.config.write_text('{ not json')
        self.service.reconcile()  # must not raise
        self.assertIn('Night Light:', self.service.config_error)
        # The last-good monitor list keeps existing gamma targets untouched.
        self.assertEqual(self.display.calls, calls)
        self.assertEqual(self.display.outputs[4]['temperature'], 4000)
        self.config.write_text(json.dumps(self.monitors))
        self.service.reconcile()
        self.assertEqual(self.service.config_error, '')

    def test_gamma_ramps_are_monotonic_and_warmer_reduces_blue(self):
        warm = array.array('H'); warm.frombytes(nl.gamma_ramps(1024, 2500))
        mild = array.array('H'); mild.frombytes(nl.gamma_ramps(1024, 5000))
        self.assertEqual(len(warm), 3072)
        for start in (0, 1024, 2048):
            self.assertEqual(warm[start], 0)
            self.assertEqual(list(warm[start:start+1024]), sorted(warm[start:start+1024]))
        self.assertEqual(warm[1023], 65535)
        self.assertLess(warm[-1], mild[-1])

    def test_unsafe_and_oversized_settings_are_rejected(self):
        victim = self.home / 'victim'; victim.write_text('{}')
        self.service.path.symlink_to(victim)
        with self.assertRaises(ValueError): nl.read_json(self.service.path, {})
        with self.assertRaises(ValueError): nl.write_json(self.service.path, {})
        self.service.path.unlink()
        self.service.path.write_text(' ' * (nl.LIMIT + 1))
        with self.assertRaises(ValueError): nl.read_json(self.service.path, {})
        with self.assertRaises(ValueError): nl.validate_preferences({'output:DP-1': {'enabled': 'yes', 'temperature': 4000}})


if __name__ == '__main__':
    unittest.main()
