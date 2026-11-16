enum GoalComparisonUnavailable { noAppearances, noAbsences, incomplete }

class GoalComparison {
  const GoalComparison.available(this.scored, this.conceded)
    : unavailable = null;
  const GoalComparison.unavailable(this.unavailable)
    : scored = null,
      conceded = null;

  final double? scored;
  final double? conceded;
  final GoalComparisonUnavailable? unavailable;
}

class GoalComparisonTeam {
  const GoalComparisonTeam({required this.color, required this.playerIds});
  final String? color;
  final List<String> playerIds;
}

/// A match snapshot. Membership comes from team_players, not current rosters.
class GoalComparisonMatch {
  const GoalComparisonMatch({
    required this.home,
    required this.away,
    required this.homeScore,
    required this.awayScore,
    this.ordinaryGoals = true,
  });
  final GoalComparisonTeam? home;
  final GoalComparisonTeam? away;
  final int? homeScore;
  final int? awayScore;
  final bool ordinaryGoals;
}

String? normalizedGoalColor(String? value) {
  final hex = value?.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase();
  return hex != null && RegExp(r'^[0-9a-f]{6}$').hasMatch(hex) ? hex : null;
}

/// Each occurrence is one whole match; absence counts never determine weights.
GoalComparison comparePlayerGoals(
  List<GoalComparisonMatch> matches,
  String playerId,
) {
  final withPlayer = <String, _Goals>{};
  final withoutPlayer = <String, _Goals>{};
  var absences = 0;
  for (final match in matches) {
    if (!match.ordinaryGoals) continue;
    if (match.homeScore == null && match.awayScore == null) continue;
    final home = match.home;
    final away = match.away;
    final gf = match.homeScore;
    final ga = match.awayScore;
    final homeColor = normalizedGoalColor(home?.color);
    final awayColor = normalizedGoalColor(away?.color);
    if (home == null ||
        away == null ||
        gf == null ||
        ga == null ||
        gf < 0 ||
        ga < 0 ||
        homeColor == null ||
        awayColor == null ||
        homeColor == awayColor ||
        home.playerIds.isEmpty ||
        away.playerIds.isEmpty ||
        home.playerIds
            .toSet()
            .intersection(away.playerIds.toSet())
            .isNotEmpty) {
      return const GoalComparison.unavailable(
        GoalComparisonUnavailable.incomplete,
      );
    }
    final atHome = home.playerIds.contains(playerId);
    final atAway = away.playerIds.contains(playerId);
    if (atHome || atAway) {
      final color = atHome ? homeColor : awayColor;
      (withPlayer[color] ??= _Goals()).add(atHome ? gf : ga, atHome ? ga : gf);
    } else {
      absences++;
      (withoutPlayer[homeColor] ??= _Goals()).add(gf, ga);
      (withoutPlayer[awayColor] ??= _Goals()).add(ga, gf);
    }
  }
  if (withPlayer.isEmpty) {
    return const GoalComparison.unavailable(
      GoalComparisonUnavailable.noAppearances,
    );
  }
  if (absences == 0) {
    return const GoalComparison.unavailable(
      GoalComparisonUnavailable.noAbsences,
    );
  }
  final appearances = withPlayer.values.fold(
    0,
    (sum, goals) => sum + goals.count,
  );
  var scored = 0.0;
  var conceded = 0.0;
  for (final entry in withPlayer.entries) {
    final baseline = withoutPlayer[entry.key];
    if (baseline == null) {
      return const GoalComparison.unavailable(
        GoalComparisonUnavailable.incomplete,
      );
    }
    final played = entry.value;
    final weight = played.count / appearances;
    scored +=
        weight *
        (played.scored / played.count - baseline.scored / baseline.count);
    conceded +=
        weight *
        (played.conceded / played.count - baseline.conceded / baseline.count);
  }
  return GoalComparison.available(scored, conceded);
}

class _Goals {
  int count = 0;
  int scored = 0;
  int conceded = 0;
  void add(int gf, int ga) {
    count++;
    scored += gf;
    conceded += ga;
  }
}
