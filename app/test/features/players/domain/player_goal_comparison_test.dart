import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fixtures/goal_comparison_data.dart';

void main() {
  GoalComparison compare(List<GoalComparisonMatch> games) =>
      comparePlayerGoals(games, 'player');

  test('weights full-match color appearances 3:1, not absence counts 2:7', () {
    final result = compare(comparisonFixture('positive'));
    // Red: 16/3 - 1 and 4/3 - 3; blue: 2 - 3 and 4 - 1.
    expect(result.scored, closeTo(3, 1e-12));
    expect(result.conceded, closeTo(-0.5, 1e-12));
  });
  test('opposite-side appearances never enter either absence baseline', () {
    final result = compare([
      goalMatch(homeScore: 6, awayScore: 2),
      goalMatch(
        homePlayers: ['other'],
        awayPlayers: ['player'],
        homeScore: 100,
        awayScore: 1,
      ),
      goalMatch(homePlayers: ['absent'], homeScore: 2, awayScore: 3),
    ]);
    expect(result.scored, 1); // .5*(6-2) + .5*(1-3)
    expect(result.conceded, 48.5); // .5*(2-3) + .5*(100-2)
  });
  test('normalizes RGB case/hash/space and keeps colors separate', () {
    expect(normalizedGoalColor(' FF0000 '), 'ff0000');
    final result = compare([
      goalMatch(homeColor: ' ff0000 '),
      goalMatch(
        homeColor: blue,
        awayColor: '#ff0000',
        homePlayers: ['absent'],
        homeScore: 3,
        awayScore: 1,
      ),
    ]);
    expect(result.scored, 5);
    expect(result.conceded, -1);
  });
  test('zero-appearance colors do not require baseline groups', () {
    expect(
      compare([
        goalMatch(),
        goalMatch(homePlayers: ['absent'], awayColor: green),
      ]).scored,
      0,
    );
  });
  test('missing played-color baseline is unavailable, not renormalized', () {
    expect(
      compare(comparisonFixture('missing-color')).unavailable,
      GoalComparisonUnavailable.incomplete,
    );
  });
  for (final scenario in ['empty', 'no-absences']) {
    test('explicit unavailable: $scenario', () {
      expect(
        compare(comparisonFixture(scenario)).unavailable,
        scenario == 'empty'
            ? GoalComparisonUnavailable.noAppearances
            : GoalComparisonUnavailable.noAbsences,
      );
    });
  }
  test('completed absence-only history means no appearances', () {
    expect(
      compare([
        goalMatch(homePlayers: ['absent']),
      ]).unavailable,
      GoalComparisonUnavailable.noAppearances,
    );
  });
  test('negative scored, positive conceded and exact zero retain signs', () {
    final negative = compare(comparisonFixture('negative'));
    expect(negative.scored, -2);
    expect(negative.conceded, 3);
    final zero = compare(comparisonFixture('zero'));
    expect(zero.scored, 0);
    expect(zero.conceded, 0);
  });
  test('unfinished and special scores are excluded, not made into goals', () {
    final result = compare([
      ...comparisonFixture('positive'),
      goalMatch(homeScore: null, awayScore: null, homeColor: null),
      goalMatch(homeScore: 999, ordinaryGoals: false),
    ]);
    expect(result.scored, closeTo(3, 1e-12));
  });
  for (final invalid in [
    goalMatch(homeScore: null),
    goalMatch(homeScore: -1),
    goalMatch(homeColor: null),
    goalMatch(homeColor: 'red'),
    goalMatch(awayColor: red),
    goalMatch(homePlayers: []),
    goalMatch(awayPlayers: ['player']),
    const GoalComparisonMatch(
      home: null,
      away: null,
      homeScore: 1,
      awayScore: 2,
    ),
  ]) {
    test(
      'incomplete completed snapshot cannot silently change the sample: $invalid',
      () {
        expect(
          compare([...comparisonFixture('positive'), invalid]).unavailable,
          GoalComparisonUnavailable.incomplete,
        );
      },
    );
  }
}
