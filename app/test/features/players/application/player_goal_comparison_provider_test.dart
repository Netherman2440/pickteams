import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import 'package:app/features/players/domain/repositories/goal_comparison_repository.dart';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fixtures/goal_comparison_data.dart';

class History implements GoalComparisonRepository {
  History(this.scenario);
  String scenario;
  final reads = <String>[];
  @override
  Future<List<GoalComparisonMatch>> getSquadHistory(String squadId) async {
    reads.add(squadId);
    if (scenario == 'error') throw StateError('history unavailable');
    return comparisonFixture(scenario);
  }
}

void main() {
  for (final scenario in [
    'positive',
    'missing-color',
    'empty',
    'no-absences',
    'error',
  ]) {
    test('squad repository orchestration: $scenario', () async {
      final history = History(scenario);
      final container = ProviderContainer(
        overrides: [
          goalComparisonRepositoryProvider.overrideWithValue(history),
        ],
      );
      addTearDown(container.dispose);
      final provider = playerGoalComparisonProvider((
        squadId: 'squad',
        playerId: 'player',
      ));
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      if (scenario == 'error') {
        await expectLater(container.read(provider.future), throwsStateError);
        expect(container.read(provider).hasError, isTrue);
        history.scenario = 'positive';
        container.invalidate(squadGoalHistoryProvider('squad'));
        expect(
          (await container.read(provider.future)).scored,
          closeTo(3, 1e-12),
        );
      } else {
        final result = await container.read(provider.future);
        expect(result.unavailable, switch (scenario) {
          'missing-color' => GoalComparisonUnavailable.incomplete,
          'empty' => GoalComparisonUnavailable.noAppearances,
          'no-absences' => GoalComparisonUnavailable.noAbsences,
          _ => null,
        });
        if (scenario == 'positive') {
          expect(result.scored, closeTo(3, 1e-12));
          expect(result.conceded, closeTo(-0.5, 1e-12));
        }
      }
      expect(history.reads, everyElement('squad'));
      expect(history.reads.length, scenario == 'error' ? 2 : 1);
    });
  }
  test('shares squad history but isolates player and squad keys', () async {
    final history = History('positive');
    final container = ProviderContainer(
      overrides: [goalComparisonRepositoryProvider.overrideWithValue(history)],
    );
    addTearDown(container.dispose);
    for (final key in [
      (squadId: 'a', playerId: 'player'),
      (squadId: 'a', playerId: 'absent'),
      (squadId: 'b', playerId: 'player'),
    ]) {
      final provider = playerGoalComparisonProvider(key);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
    }
    expect(history.reads, ['a', 'b']);
  });
}
