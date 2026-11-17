import 'package:app/features/matches/application/match_level_providers.dart';
import 'package:app/features/matches/application/save_star_thresholds.dart';
import 'package:app/features/matches/domain/match_level.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/repositories/match_level_repository.dart';
import 'package:app/features/matches/presentation/controllers/squad_matches_notifier.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class LevelFixture implements MatchLevelRepository {
  final settings = <String, MatchLevelThresholds?>{
    'a': MatchLevelThresholds([10, 30, 70, 90, 150]),
  };
  bool failLoad = false;
  bool failSave = false;
  int reads = 0;
  int completed = 26;
  @override
  Future<MatchLevelThresholds?> loadThresholds(String squadId) async {
    if (failLoad) throw StateError('load failure');
    return settings[squadId];
  }

  @override
  Future<void> saveThresholds(
    String squadId,
    MatchLevelThresholds thresholds,
  ) async {
    if (failSave) throw StateError('save failure');
    settings[squadId] = thresholds;
  }

  @override
  Future<SquadMatchLevels> loadHistory(String squadId) async {
    reads++;
    return SquadMatchLevels(
      completedMatches: completed,
      means: {'m': 50, 'missing': null},
    );
  }
}

class EmptyMatches extends SquadMatchesNotifier {
  @override
  AsyncValue<List<Match>> build(String squadId) => AsyncData(<Match>[]);
}

void main() {
  test(
    'one computation shared across consumers, settings refresh and squad isolation',
    () async {
      final repo = LevelFixture();
      final container = ProviderContainer(
        overrides: [
          matchLevelRepositoryProvider.overrideWithValue(repo),
          squadMatchesProvider.overrideWith(EmptyMatches.new),
        ],
      );
      addTearDown(container.dispose);
      final one = container.listen(squadMatchLevelsProvider('a'), (_, _) {});
      final two = container.listen(squadMatchLevelsProvider('a'), (_, _) {});
      addTearDown(one.close);
      addTearDown(two.close);
      expect(await container.read(squadMatchLevelsProvider('a').future), {
        'm': 2.5,
      });
      expect(repo.reads, 1);
      expect(await container.read(squadMatchLevelsProvider('b').future), {
        'm': 1,
      });
      expect(
        repo.settings['b'],
        isNull,
        reason: 'Baseline never writes an override',
      );
      await container
          .read(saveStarThresholdsProvider)
          .execute(
            squadId: 'a',
            role: SquadRole.owner,
            values: [1, 2, 3, 4, 5],
          );
      expect(await container.read(squadMatchLevelsProvider('a').future), {
        'm': 5,
      });
      repo.completed = 25;
      container.invalidate(squadMatchesProvider('a'));
      expect(
        await container.read(squadMatchLevelsProvider('a').future),
        isEmpty,
      );
    },
  );
  test(
    'failed settings load stays an error, not fabricated defaults',
    () async {
      final repo = LevelFixture()..failLoad = true;
      final container = ProviderContainer(
        overrides: [
          matchLevelRepositoryProvider.overrideWithValue(repo),
          squadMatchesProvider.overrideWith(EmptyMatches.new),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(starThresholdsProvider('a').future),
        throwsStateError,
      );
      expect(repo.reads, 0);
    },
  );
  test(
    'save use case owner success, invalid values and all non-owner roles denied',
    () async {
      final repo = LevelFixture();
      final save = SaveStarThresholds(repo);
      await save.execute(
        squadId: 'b',
        role: SquadRole.owner,
        values: [1, 2, 3, 4, 5],
      );
      expect(repo.settings['b']!.full, [1, 2, 3, 4, 5]);
      for (final role in <SquadRole?>[
        null,
        ...SquadRole.values.where((r) => r != SquadRole.owner),
      ]) {
        await expectLater(
          save.execute(squadId: 'b', role: role, values: [2, 3, 4, 5, 6]),
          throwsStateError,
        );
      }
      await expectLater(
        save.execute(
          squadId: 'b',
          role: SquadRole.owner,
          values: [1, 1, 3, 4, 5],
        ),
        throwsArgumentError,
      );
      repo.failSave = true;
      await expectLater(
        save.execute(
          squadId: 'b',
          role: SquadRole.owner,
          values: [2, 3, 4, 5, 6],
        ),
        throwsStateError,
      );
      expect(repo.settings['b']!.full, [1, 2, 3, 4, 5]);
    },
  );
}
