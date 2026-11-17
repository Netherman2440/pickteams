import 'package:app/features/matches/domain/match_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Synthetic thresholds only, deliberately not a proposed calibration.
  final thresholds = MatchLevelThresholds([10, 30, 70, 90, 150]);
  for (final scale in [thresholds, MatchLevelThresholds.calibratedBaseline]) {
    test('all full/midpoint boundaries and extremes: ${scale.full}', () {
      final boundaries = [
        for (var i = 0; i < 5; i++) ...[
          scale.full[i],
          if (i < 4) scale.halves[i],
        ],
      ];
      for (var i = 0; i < boundaries.length; i++) {
        final expected = 1 + i * .5;
        expect(scale.rating(boundaries[i]), expected);
        expect(scale.rating(boundaries[i] + .0001), expected);
        expect(scale.rating(boundaries[i] - .0001), i == 0 ? 1 : expected - .5);
      }
      expect(scale.rating(-1e100), 1);
      expect(scale.rating(1e100), 5);
    });
  }
  test(
    'calibrated baseline has exact decimal-derived midpoint boundaries and is immutable',
    () {
      final baseline = MatchLevelThresholds.calibratedBaseline;
      expect(baseline.full, [49.8, 56.1, 58.0, 59.8, 62.9]);
      expect(baseline.halves, [52.95, 57.05, 58.9, 61.35]);
      for (var i = 0; i < 4; i++) {
        expect(baseline.rating([52.95, 57.05, 58.9, 61.35][i]), i + 1.5);
      }
      expect(() => baseline.full[0] = 0, throwsUnsupportedError);
    },
  );
  test(
    'decimal midpoint handles scientific notation and large finite anchors without overflow',
    () {
      final scale = MatchLevelThresholds([-1e308, -5e307, 0, 5e307, 1e308]);
      expect(scale.halves, [-7.5e307, -2.5e307, 2.5e307, 7.5e307]);
      expect(scale.halves.every((v) => v.isFinite), isTrue);
      expect(
        MatchLevelThresholds([5e-324, 1e-200, 1, 1e200, 1e308]).halves.first,
        5e-201,
      );
    },
  );
  test('rejects lengths, non-finite, repeated and unordered thresholds', () {
    for (final values in <List<double>>[
      [],
      [1, 2, 3, 4],
      [1, 2, 3, 4, 5, 6],
      [1, 2, 2, 4, 5],
      [5, 4, 3, 2, 1],
      [1, 2, 3, 4, double.nan],
      [1, 2, 3, 4, double.infinity],
      [double.negativeInfinity, 2, 3, 4, 5],
    ]) {
      expect(() => MatchLevelThresholds(values), throwsArgumentError);
    }
    expect(() => thresholds.rating(double.nan), throwsArgumentError);
    expect(() => thresholds.rating(double.infinity), throwsArgumentError);
  });
  test(
    'all players equal weight, no team or rotation factor; missing hides',
    () {
      expect(historicalMatchMean([10, 10, 100]), 40);
      expect(historicalMatchMean([]), isNull);
      expect(historicalMatchMean([10, null, 100]), isNull);
      expect(historicalMatchMean([10, double.nan]), isNull);
      expect(historicalMatchMean([10, double.infinity]), isNull);
    },
  );
}
