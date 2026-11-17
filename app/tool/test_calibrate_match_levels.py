"""Arithmetic checks only. Owner-supplied record counts are not independently read."""
from itertools import product
from pathlib import Path
import re
import unittest
from calibrate_match_levels import calibrate, owner_calibration


class CalibrationTest(unittest.TestCase):
    def test_owner_aggregate_calculation_and_committed_baseline_agree(self):
        result = owner_calibration()
        self.assertEqual(result['full'], ['49.8', '56.1', '58.0', '59.8', '62.9'])
        self.assertEqual(result['halves'], ['52.95', '57.05', '58.9', '61.35'])
        self.assertAlmostEqual(result['cdf_endpoints'][0], 0.0017320663255985247)
        self.assertAlmostEqual(result['cdf_endpoints'][1], 0.9532321558305068)
        source = (Path(__file__).parents[1] / 'lib/features/matches/domain/match_level.dart').read_text()
        baseline = re.search(r'calibratedBaseline = MatchLevelThresholds\(\[(.*?)\]', source, re.S)[1]
        self.assertEqual([float(v) for v in re.findall(r'\d+\.\d+', baseline)], [float(v) for v in result['full']])

    def test_rounding_stable_within_reported_precision(self):
        # Interior of each reported rounding bin, not a confidence interval.
        for mu, sd, low, high in product(
            [58.1409 - .000049, 58.1409 + .000049],
            [2.85331 - .0000049, 2.85331 + .0000049],
            [49.8 - .049, 49.8 + .049],
            [62.926 - .00049, 62.926 + .00049],
        ):
            self.assertEqual(calibrate(mu, sd, low, high)['full'], owner_calibration()['full'])

    def test_degenerate_inputs_are_not_a_scale(self):
        for args in [(50, 0, 40, 60), (50, -1, 40, 60), (50, 2, 40, 40), (50, 2, 60, 40)]:
            with self.assertRaises(ValueError):
                calibrate(*args)
