import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/domain/services/player_match_perspective.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GoalComparisonMatch snapshot({
    String id = 'm',
    List<String> home = const ['p'],
    List<String> away = const ['other'],
    bool ordinary = true,
  }) => GoalComparisonMatch(
    matchId: id,
    home: GoalComparisonTeam(color: null, playerIds: home),
    away: GoalComparisonTeam(color: null, playerIds: away),
    homeScore: 99,
    awayScore: 99,
    ordinaryGoals: ordinary,
  );
  Match match(int? home, int? away) => Match(
    matchId: 'm',
    squadId: 's',
    createdAt: DateTime(2026),
    homeScore: home,
    awayScore: away,
  );

  for (final (home, away, atHome, outcome) in [
    (5, 2, true, PlayerMatchOutcome.win),
    (5, 2, false, PlayerMatchOutcome.loss),
    (2, 4, false, PlayerMatchOutcome.win),
    (2, 4, true, PlayerMatchOutcome.loss),
    (0, 0, true, PlayerMatchOutcome.draw),
    (0, 0, false, PlayerMatchOutcome.draw),
  ]) {
    test(
      'persisted ${atHome ? 'home' : 'away'} membership gives $outcome for $home:$away, not snapshot scores',
      () {
        final result = PlayerMatchPerspective.fromMatch(
          match(home, away),
          snapshot(
            home: atHome ? ['p'] : ['other'],
            away: atHome ? ['other'] : ['p'],
          ),
          'p',
        );
        expect(result.side, atHome ? Side.home : Side.away);
        expect(result.outcome, outcome);
      },
    );
  }
  for (final bad in [
    null,
    snapshot(id: 'different'),
    snapshot(home: []),
    snapshot(home: ['other']),
    snapshot(home: ['p'], away: ['p']),
    snapshot(home: ['p', 'overlap'], away: ['other', 'overlap']),
    const GoalComparisonMatch(
      matchId: 'm',
      home: null,
      away: null,
      homeScore: 5,
      awayScore: 2,
    ),
  ]) {
    test('missing, absent or ambiguous membership stays neutral: $bad', () {
      final result = PlayerMatchPerspective.fromMatch(match(5, 2), bad, 'p');
      expect(result.side, isNull);
      expect(result.outcome, isNull);
    });
  }
  for (final (home, away) in [
    (null, null),
    (0, null),
    (null, 0),
    (-1, 0),
    (0, -1),
  ]) {
    test('unscored/incomplete/invalid $home:$away does not imply a result', () {
      final result = PlayerMatchPerspective.fromMatch(
        match(home, away),
        snapshot(),
        'p',
      );
      expect(result.side, Side.home);
      expect(result.outcome, isNull);
    });
  }
  test('special result never becomes an ordinary win', () {
    final result = PlayerMatchPerspective.fromMatch(
      match(5, 2),
      snapshot(ordinary: false),
      'p',
    );
    expect(result.side, Side.home);
    expect(result.outcome, isNull);
  });
}
