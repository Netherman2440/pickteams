import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'player_goal_comparison.dart';

enum PlayerMatchOutcome { win, draw, loss }

/// Only persisted membership identifies a side. Names, colors, ranking deltas
/// and fixture positions cannot determine which team a player represented.
class PlayerMatchPerspective {
  const PlayerMatchPerspective({this.side, this.outcome});
  final Side? side;
  final PlayerMatchOutcome? outcome;

  factory PlayerMatchPerspective.fromMatch(
    Match match,
    GoalComparisonMatch? snapshot,
    String playerId,
  ) {
    if (snapshot == null || snapshot.matchId != match.matchId) {
      return const PlayerMatchPerspective();
    }
    final home = snapshot.home?.playerIds.toSet();
    final away = snapshot.away?.playerIds.toSet();
    if (home == null ||
        away == null ||
        home.isEmpty ||
        away.isEmpty ||
        home.intersection(away).isNotEmpty) {
      return const PlayerMatchPerspective();
    }
    final atHome = home.contains(playerId);
    final atAway = away.contains(playerId);
    if (!atHome && !atAway) return const PlayerMatchPerspective();
    final side = atHome ? Side.home : Side.away;
    final hs = match.homeScore;
    final aws = match.awayScore;
    if (!snapshot.ordinaryGoals ||
        hs == null ||
        aws == null ||
        hs < 0 ||
        aws < 0) {
      return PlayerMatchPerspective(side: side);
    }
    final scored = atHome ? hs : aws;
    final conceded = atHome ? aws : hs;
    return PlayerMatchPerspective(
      side: side,
      outcome: scored == conceded
          ? PlayerMatchOutcome.draw
          : scored > conceded
          ? PlayerMatchOutcome.win
          : PlayerMatchOutcome.loss,
    );
  }
}
