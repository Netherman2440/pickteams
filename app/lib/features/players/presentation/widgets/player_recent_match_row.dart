import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/services/player_goal_comparison.dart';
import '../../domain/services/player_match_perspective.dart';

class PlayerRecentMatchRow extends StatelessWidget {
  const PlayerRecentMatchRow({
    super.key,
    required this.match,
    required this.playerId,
    this.snapshot,
  });
  final Match match;
  final String playerId;
  final GoalComparisonMatch? snapshot;

  @override
  Widget build(BuildContext context) {
    final perspective = PlayerMatchPerspective.fromMatch(
      match,
      snapshot,
      playerId,
    );
    final away = perspective.side == Side.away;
    final known = perspective.side != null;
    final first = away ? match.awayScore : match.homeScore;
    final second = away ? match.homeScore : match.awayScore;
    final outcome = switch (perspective.outcome) {
      PlayerMatchOutcome.win => 'Wygrana',
      PlayerMatchOutcome.draw => 'Remis',
      PlayerMatchOutcome.loss => 'Porażka',
      null =>
        !known
            ? 'Brak danych o stronie'
            : match.homeScore == null || match.awayScore == null
            ? 'Brak wyniku'
            : 'Wynik specjalny lub niepełny',
    };
    final side = !known
        ? 'Gospodarze : goście'
        : away
        ? 'Goście'
        : 'Gospodarze';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('dd.MM.yyyy').format(match.createdAt.toLocal()),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(side, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(outcome, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(
              '${first ?? '—'} : ${second ?? '—'}',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
