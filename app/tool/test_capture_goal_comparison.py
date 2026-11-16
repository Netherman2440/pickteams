import unittest
from urllib.parse import parse_qs, urlparse

from capture_goal_comparison import SCENARIOS, VIEWPORTS, check_diagnostics, fixture_url


class CaptureContractTest(unittest.TestCase):
    def test_fixture_cases_and_browser_dimensions(self):
        self.assertEqual(set(SCENARIOS), {
            'positive', 'negative', 'zero', 'rounded-zero',
            'missing-color', 'empty', 'no-absences', 'error',
        })
        self.assertEqual(len(VIEWPORTS) * len(SCENARIOS), 32)
        self.assertIn((320, 900, 1.6), VIEWPORTS)

    def test_url_labels_scenario_and_scale_without_live_credentials(self):
        url = fixture_url('http://127.0.0.1:18859/', 'missing-color', 1.6)
        self.assertEqual(parse_qs(urlparse(url).query), {
            'comparison': ['missing-color'], 'scale': ['1.6'], 'role': ['viewer'],
        })
        for base in ['https://example.com', 'http://10.0.0.1', 'file:///tmp/web']:
            with self.assertRaises(ValueError):
                fixture_url(base, 'positive', 1)
        with self.assertRaises(ValueError):
            fixture_url('http://localhost:18859', 'unknown', 1)

    def test_render_errors_and_document_overflow_fail_capture(self):
        check_diagnostics([], ['Flutter initialized'], 320, 320)
        for errors, console, width in [
            (['uncaught'], [], 320),
            ([], ['A RenderFlex overflowed by 1 pixels'], 320),
            ([], ['EXCEPTION CAUGHT BY WIDGETS'], 320),
            ([], [], 321),
        ]:
            with self.assertRaises(AssertionError):
                check_diagnostics(errors, console, width, 320)


if __name__ == '__main__':
    unittest.main()
