"""Reproduce #61 calibration from owner-supplied aggregates, not personal rows."""
from decimal import Decimal, ROUND_HALF_UP
from statistics import NormalDist
import json

OWNER_INPUT = {
    'source': 'https://github.com/Netherman2440/pickteams/issues/61#issuecomment-6941297324',
    'reported_reader': 'dot, public RLS GET, 2026-11-16 19:14 UTC',
    'squad': 'Politechnika Lubelska',
    'through': '2026-11-13 inclusive; created_at in Europe/Warsaw; played_at NULL',
    'completed_matches': 54,
    'match_player_pairs': 791,
    'match_specific_rankings': 791,
    'reported_missing_duplicate_nonfinite': 0,
    'mean': '58.1409', 'population_sd': '2.85331', 'minimum': '49.8', 'maximum': '62.926',
}


def calibrate(mean, population_sd, minimum, maximum):
    if not population_sd > 0 or not minimum < maximum:
        raise ValueError('Positive population SD and nonzero observed range required')
    distribution = NormalDist(mean, population_sd)
    low, high = distribution.cdf(minimum), distribution.cdf(maximum)
    raw = [distribution.inv_cdf(low + (high - low) * i / 4) for i in range(5)]
    full = [Decimal(str(v)).quantize(Decimal('0.1'), rounding=ROUND_HALF_UP) for v in raw]
    if any(a >= b for a, b in zip(full, full[1:])):
        raise ValueError('Rounded full thresholds must strictly increase')
    halves = [(a + b) / 2 for a, b in zip(full, full[1:])]
    return {'cdf_endpoints': [low, high], 'raw_full': raw,
            'full': [str(v) for v in full], 'halves': [str(v) for v in halves]}


def owner_calibration():
    return calibrate(*(float(OWNER_INPUT[k]) for k in ('mean', 'population_sd', 'minimum', 'maximum')))


if __name__ == '__main__':
    print(json.dumps({'owner_supplied_input': OWNER_INPUT, 'independent_arithmetic': owner_calibration()}, indent=2))
