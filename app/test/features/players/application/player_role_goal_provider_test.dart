import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import 'package:app/features/players/application/usecases/get_squad_players_usecase.dart';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fixtures/role_goal_app.dart';

void main() {
  late RoleHistory history;
  late RoleRoster roster;
  late ProviderContainer container;
  const key = (squadId: 's', playerId: 'player');
  setUp(() {
    history = RoleHistory();
    roster = RoleRoster();
    container = ProviderContainer(
      overrides: [
        goalComparisonRepositoryProvider.overrideWithValue(history),
        getSquadPlayersUseCaseProvider.overrideWithValue(
          GetSquadPlayersUseCase(roster),
        ),
      ],
    );
    container.listen(playerRoleGoalComparisonProvider(key), (_, _) {});
    container.listen(squadRoleGoalComparisonsProvider('s'), (_, _) {});
  });
  tearDown(() => container.dispose());

  test(
    'both screens share one paged history, identical values/counts, and refresh',
    () async {
      final player = await container.read(
        playerRoleGoalComparisonProvider(key).future,
      );
      final squad = await container.read(
        squadRoleGoalComparisonsProvider('s').future,
      );
      final row = squad.singleWhere((row) => row.player.playerId == 'player');
      for (final role in GoalRole.values) {
        expect(row.comparison[role]!.scored, player[role]!.scored);
        expect(row.comparison[role]!.conceded, player[role]!.conceded);
        expect(row.comparison[role]!.withPlayer, player[role]!.withPlayer);
        expect(
          row.comparison[role]!.withoutPlayer,
          player[role]!.withoutPlayer,
        );
      }
      expect(history.reads, 1);
      expect(roster.reads, 1);
      history.matches = [];
      container.invalidate(squadGoalHistoryProvider('s'));
      final refreshed = await container.read(
        playerRoleGoalComparisonProvider(key).future,
      );
      final refreshedRows = await container.read(
        squadRoleGoalComparisonsProvider('s').future,
      );
      expect(refreshed[GoalRole.home]!.scored, isNull);
      expect(refreshedRows.first.comparison[GoalRole.home]!.scored, isNull);
      expect(history.reads, 2);
    },
  );
  test('history failure reaches both screens; shared retry recovers', () async {
    history.fail = true;
    container.invalidate(squadGoalHistoryProvider('s'));
    await expectLater(
      container.read(playerRoleGoalComparisonProvider(key).future),
      throwsStateError,
    );
    await expectLater(
      container.read(squadRoleGoalComparisonsProvider('s').future),
      throwsStateError,
    );
    history.fail = false;
    container.invalidate(squadGoalHistoryProvider('s'));
    expect(
      (await container.read(
        playerRoleGoalComparisonProvider(key).future,
      ))[GoalRole.home]!.scored,
      3,
    );
    expect(
      await container.read(squadRoleGoalComparisonsProvider('s').future),
      hasLength(3),
    );
  });
  test(
    'roster failure does not turn into an empty list or block player comparison',
    () async {
      roster.fail = true;
      await expectLater(
        container.read(squadRoleGoalComparisonsProvider('s').future),
        throwsStateError,
      );
      expect(
        (await container.read(
          playerRoleGoalComparisonProvider(key).future,
        ))[GoalRole.away]!.conceded,
        2,
      );
      roster.fail = false;
      container.invalidate(squadRoleGoalComparisonsProvider('s'));
      expect(
        await container.read(squadRoleGoalComparisonsProvider('s').future),
        hasLength(3),
      );
      expect(history.reads, 1);
    },
  );
}
