import 'package:app/features/matches/domain/match_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Synthetic thresholds only, deliberately not a proposed calibration.
  final thresholds = MatchLevelThresholds([10, 30, 70, 90, 150]);
  test('all full and midpoint boundaries promote on equality and clamp', () {
    final boundaries = <double>[10, 20, 30, 50, 70, 80, 90, 120, 150];
    for (var i = 0; i < boundaries.length; i++) {
      final expected = 1 + i * .5;
      expect(thresholds.rating(boundaries[i]), expected);
      expect(thresholds.rating(boundaries[i] + .0001), expected);
      expect(
        thresholds.rating(boundaries[i] - .0001),
        i == 0 ? 1 : expected - .5,
      );
    }
    expect(thresholds.rating(-1e100), 1);
    expect(thresholds.rating(1e100), 5);
    expect(thresholds.halves, [20, 50, 80, 120]);
  });
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
