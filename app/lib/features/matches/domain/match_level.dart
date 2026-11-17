/// Full-star thresholds, either a squad override or the calibrated baseline.
class MatchLevelThresholds {
  MatchLevelThresholds(Iterable<double> values)
    : full = List<double>.unmodifiable(values) {
    if (full.length != 5 ||
        full.any((value) => !value.isFinite) ||
        List.generate(4, (i) => full[i] >= full[i + 1]).any((v) => v)) {
      throw ArgumentError('Wymagane jest pięć skończonych, rosnących progów.');
    }
  }

  /// Owner-supplied aggregate calibration for Politechnika Lubelska through
  /// 2026-11-13. See docs/features/match-level-calibration.md for provenance.
  static final calibratedBaseline = MatchLevelThresholds([
    49.8,
    56.1,
    58.0,
    59.8,
    62.9,
  ]);

  final List<double> full;

  late final List<double> halves = List<double>.unmodifiable(
    List.generate(4, (i) => _decimalMidpoint(full[i], full[i + 1])),
  );

  /// Equality promotes to the new step; scores outside the scale clamp to 1–5.
  double rating(double mean) {
    if (!mean.isFinite) throw ArgumentError.value(mean, 'mean');
    var result = 1.0;
    for (var i = 0; i < 4; i++) {
      if (mean >= halves[i]) result = i + 1.5;
      if (mean >= full[i + 1]) result = i + 2.0;
    }
    return result;
  }
}

// Average the displayed decimal inputs before converting once to binary double.
// This avoids 59.8/2 + 62.9/2 producing 61.349999999999994, and avoids overflow.
double _decimalMidpoint(double a, double b) {
  (BigInt, int) parts(double value) {
    final scientific = value.toString().toLowerCase().split('e');
    final mantissa = scientific.first.split('.');
    final exponent =
        (scientific.length == 2 ? int.parse(scientific.last) : 0) -
        (mantissa.length == 2 ? mantissa.last.length : 0);
    return (BigInt.parse(mantissa.join()), exponent);
  }

  final (left, leftExponent) = parts(a);
  final (right, rightExponent) = parts(b);
  final exponent = leftExponent < rightExponent ? leftExponent : rightExponent;
  final sum =
      left * BigInt.from(10).pow(leftExponent - exponent) +
      right * BigInt.from(10).pow(rightExponent - exponent);
  return double.parse('${sum * BigInt.from(5)}e${exponent - 1}');
}

/// A missing or non-finite historical value hides the level, never substitutes
/// a current ranking. Every participant has equal weight, including odd rosters.
double? historicalMatchMean(Iterable<double?> rankings) {
  final values = rankings.toList();
  if (values.isEmpty || values.any((v) => v == null || !v.isFinite)) {
    return null;
  }
  return values.fold<double>(0, (sum, v) => sum + v! / values.length);
}

bool matchLevelEligible(int completedMatches) => completedMatches > 25;
