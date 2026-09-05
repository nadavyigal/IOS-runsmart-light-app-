import contextlib
import datetime
import io
import unittest
from unittest.mock import patch
import measurement_contract as contract

class ContractReviewTests(unittest.TestCase):
    def test_resumely_is_routed_to_its_corrected_contract_without_a_query(self):
        with patch.object(contract, 'load_key', side_effect=AssertionError('must not load')), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(contract.run('resumely', '28'), 2)

    def test_incomplete_query_does_not_report_zero_users(self):
        response = io.StringIO('{"query_status": "running"}')
        with patch.object(contract.urllib.request, 'urlopen', return_value=response), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as stopped:
                contract.hogql('synthetic', 171597, 'SELECT count() FROM events')
            self.assertEqual(stopped.exception.code, 1)

    def test_missing_key_does_not_read_credential_files(self):
        with patch.dict(contract.os.environ, {}, clear=True), patch.object(contract.Path, 'read_text', side_effect=AssertionError('must not read')), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as stopped:
                contract.load_key()
            self.assertEqual(stopped.exception.code, 2)

    def test_completed_day_window_current_person_exclusion_and_no_d7_claim(self):
        class Clock(datetime.datetime):
            @classmethod
            def now(cls, tz=None): return cls(2026, 9, 20, 12, tzinfo=datetime.timezone.utc)
        queries = []
        def fake_query(key, project, sql):
            queries.append(sql)
            if 'GROUP BY lib' in sql: return [['posthog-ios', 20, 10]]
            if 'GROUP BY event' in sql: return [['app_launched', 10], ['sign_in_wall_reached', 10]]
            if 'GROUP BY app_version' in sql: return [['1.1.7', '32', 20, 10, '2026-09-03T00:00:00+00:00', '2026-09-19T00:00:00+00:00']]
            if 'GROUP BY is_internal' in sql: return [[0, 10, 20]]
            return [[3, 10]]
        output = io.StringIO()
        with patch.object(contract, 'datetime', Clock), patch.object(contract, 'load_key', return_value='synthetic'), patch.object(contract, 'apple_lookup', return_value=('1.1.7', '2026-09-02T19:44:12Z')), patch.object(contract, 'hogql', side_effect=fake_query), contextlib.redirect_stdout(output):
            self.assertEqual(contract.run('runsmart', '32'), 0)
        self.assertTrue(all("timestamp < toDateTime('2026-09-20 00:00:00')" in query for query in queries))
        self.assertIn('SELECT id FROM persons', queries[-1])
        self.assertIn('SELECT id FROM persons', queries[-2])
        self.assertNotIn('D7 measurable:', output.getvalue())
        self.assertIn('not D7 activation', output.getvalue())

if __name__ == '__main__': unittest.main()
