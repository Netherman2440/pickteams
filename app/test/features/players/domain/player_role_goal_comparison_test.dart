import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fixtures/goal_comparison_data.dart';
import '../../../fixtures/role_goal_app.dart';

void main() {
  void expectFixture(List<GoalComparisonMatch> matches) {
    final result = comparePlayerRoleGoals(matches, 'player');
    for (final role in GoalRole.values) {
      expect(result[role]!.withPlayer, 1);
      expect(result[role]!.withoutPlayer, 1);
      expect(result[role]!.scored, 3);
      expect(result[role]!.conceded, role == GoalRole.home ? -1 : 2);
    }
  }

  test(
    'opposite-role appearance is not absence; same-role goals on both sides',
    () {
      expectFixture(roleGoalFixture());
    },
  );
  test('swapped, repeated, missing and invalid colors do not change roles', () {
    for (final colors in [
      (blue, red),
      (red, red),
      (null, null),
      ('invalid', ''),
    ]) {
      expectFixture(
        roleGoalFixture(homeColor: colors.$1, awayColor: colors.$2),
      );
    }
  });
  test('missing appearances or absences never produce a numeric delta', () {
    for (final matches in [
      <GoalComparisonMatch>[],
      [goalMatch()],
      [
        goalMatch(homePlayers: ['other'], awayPlayers: ['third']),
      ],
    ]) {
      final result = comparePlayerRoleGoals(matches, 'player');
      for (final role in GoalRole.values) {
        expect(result[role]!.scored, isNull);
        expect(result[role]!.conceded, isNull);
      }
    }
    final homeOnly = comparePlayerRoleGoals([
      goalMatch(),
      goalMatch(homePlayers: ['third']),
    ], 'player');
    expect(homeOnly[GoalRole.home]!.scored, 0);
    expect(homeOnly[GoalRole.away]!.scored, isNull);
    expect(homeOnly[GoalRole.away]!.withoutPlayer, 1);
  });
  test(
    'unplayed and ineligible matches are ignored, including their malformed data',
    () {
      expectFixture([
        ...roleGoalFixture(),
        goalMatch(homeScore: null, awayScore: null),
        goalMatch(homeScore: -1, ordinaryGoals: false),
      ]);
    },
  );
  test(
    'malformed scored history invalidates deltas without inventing sample counts',
    () {
      for (final malformed in [
        goalMatch(homeScore: null),
        goalMatch(awayScore: -1),
        goalMatch(homePlayers: []),
        goalMatch(awayPlayers: ['player']),
        const GoalComparisonMatch(
          home: null,
          away: null,
          homeScore: 1,
          awayScore: 2,
        ),
      ]) {
        final result = comparePlayerRoleGoals([
          ...roleGoalFixture(),
          malformed,
        ], 'player');
        for (final role in GoalRole.values) {
          expect(result[role]!.incomplete, isTrue);
          expect(result[role]!.scored, isNull);
          expect(result[role]!.conceded, isNull);
          expect(result[role]!.withPlayer, 1);
          expect(result[role]!.withoutPlayer, 1);
        }
      }
    },
  );
  for (final measure in GoalMeasure.values) {
    for (final reverse in [false, true]) {
      test(
        '${measure.name}: beneficial default, reverse=$reverse, missing last, ID ties',
        () {
          Map<GoalRole, RoleGoalComparison> value(double? v) => {
            for (final role in GoalRole.values)
              role: RoleGoalComparison(
                withPlayer: 1,
                withoutPlayer: 1,
                scored: v,
                conceded: v,
              ),
          };
          final values = {
            'missing-z': value(null),
            'b': value(3),
            'a': value(3),
            'low': value(-1),
            'missing-a': value(null),
          };
          final ids = values.keys.toList()
            ..sort(
              (a, b) => compareGoalMeasure(
                measure,
                a,
                values[a]!,
                b,
                values[b]!,
                reverse: reverse,
              ),
            );
          expect(
            ids,
            (measure.conceded != reverse)
                ? ['low', 'a', 'b', 'missing-a', 'missing-z']
                : ['a', 'b', 'low', 'missing-a', 'missing-z'],
          );
        },
      );
    }
  }
}
