/// Squad-specific full-star thresholds. No uncalibrated production defaults.
class MatchLevelThresholds {
  MatchLevelThresholds(Iterable<double> values)
    : full = List<double>.unmodifiable(values) {
    if (full.length != 5 ||
        full.any((value) => !value.isFinite) ||
        List.generate(4, (i) => full[i] >= full[i + 1]).any((v) => v)) {
      throw ArgumentError('Wymagane jest pięć skończonych, rosnących progów.');
    }
  }

  final List<double> full;

  List<double> get halves =>
      List.generate(4, (i) => full[i] / 2 + full[i + 1] / 2);

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
