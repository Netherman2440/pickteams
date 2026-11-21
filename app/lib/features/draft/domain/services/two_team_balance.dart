import 'dart:math';

import 'package:app/core/utils/team_ranking.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_proposal.dart';
import 'package:app/features/players/domain/entities/player.dart';

/// Fixed draft-wide scales. Unequal teams compare only existing pairs.
class TwoTeamBalance {
  TwoTeamBalance(List<Player> availablePlayers, this.appearances)
    : experienceScale = availablePlayers.fold<int>(
        1,
        (maximum, player) => max(maximum, appearances[player.playerId] ?? 0),
      );

  final Map<String, int> appearances;
  final int experienceScale;

  double rankingPairs(Draft draft) =>
      _pairs(draft, (player) => player.ranking, 99);

  double experiencePairs(Draft draft) => _pairs(
    draft,
    (player) => (appearances[player.playerId] ?? 0).toDouble(),
    experienceScale.toDouble(),
  );

  final _secondaryScores = <Draft, double>{};

  double secondary(Draft draft) => _secondaryScores.putIfAbsent(
    draft,
    () => 0.5 * rankingPairs(draft) + 0.5 * experiencePairs(draft),
  );

  /// Compare exact effective differences, never rounded labels or epsilon ties.
  int compare(
    DraftProposal a,
    DraftProposal b, {
    required bool playWithSubstitute,
  }) {
    double difference(Draft draft) {
      final teams = draft.teams;
      double effective(int index) => effectiveTeamRanking(
        totalRanking: teams[index].totalRanking,
        teamSize: teams[index].players.length,
        opponentTeamSize: teams[1 - index].players.length,
        playWithSubstitute: playWithSubstitute,
      );
      return (effective(0) - effective(1)).abs();
    }

    final primary = difference(a.draft).compareTo(difference(b.draft));
    if (primary != 0) return primary;
    final pairs = secondary(a.draft).compareTo(secondary(b.draft));
    if (pairs != 0) return pairs;
    // Retain existing rule/position preferences on a complete balance tie.
    final penalty = a.penaltyScore.compareTo(b.penaltyScore);
    if (penalty != 0) return penalty;
    return a.signature.compareTo(b.signature);
  }

  double _pairs(Draft draft, double Function(Player) value, double scale) {
    final values = draft.teams
        .map(
          (team) =>
              team.players.map(value).toList()..sort((a, b) => b.compareTo(a)),
        )
        .toList();
    final count = min(values[0].length, values[1].length);
    if (count == 0) return 0;
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      sum += (values[0][i] - values[1][i]).abs();
    }
    return sum / count / scale;
  }
}
