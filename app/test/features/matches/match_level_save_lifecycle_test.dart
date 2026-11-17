import 'dart:async';
import 'package:app/features/matches/application/match_level_providers.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/match_level.dart';
import 'package:app/features/matches/domain/repositories/match_level_repository.dart';
import 'package:app/features/matches/presentation/controllers/squad_matches_notifier.dart';
import 'package:app/features/squads/domain/entities/squad.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/pages/squad_star_thresholds_page.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingThresholds implements MatchLevelRepository {
  final pending = Completer<void>();
  final values = <String, MatchLevelThresholds>{
    'a': MatchLevelThresholds([10, 30, 70, 90, 150]),
    'b': MatchLevelThresholds([20, 40, 80, 100, 160]),
  };
  final loads = <String>[];
  final saves = <String>[];
  @override
  Future<MatchLevelThresholds?> loadThresholds(String id) async {
    loads.add(id);
    return values[id];
  }

  @override
  Future<void> saveThresholds(
    String id,
    MatchLevelThresholds thresholds,
  ) async {
    saves.add(id);
    await pending.future;
    values[id] = thresholds;
  }

  @override
  Future<SquadMatchLevels> loadHistory(String id) async =>
      const SquadMatchLevels(completedMatches: 26, means: {'m': 50});
}

class StableMatches extends SquadMatchesNotifier {
  @override
  AsyncValue<List<Match>> build(String squadId) => const AsyncData([]);
}

void main() {
  for (final switchSquad in [false, true]) {
    testWidgets(
      'pending save invalidates original squad after ${switchSquad ? 'squad switch' : 'page disposal'} with retained ratings',
      (tester) async {
        tester.view.physicalSize = const Size(600, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = PendingThresholds();
        final container = ProviderContainer(
          overrides: [
            matchLevelRepositoryProvider.overrideWithValue(repository),
            squadMatchesProvider.overrideWith(StableMatches.new),
            squadDetailProvider.overrideWith(
              (ref, id) async => Squad(
                squadId: id,
                ownerId: 'owner',
                name: id,
                visibility: SquadVisibility.private,
                sportType: SportType.football,
                role: SquadRole.owner,
                createdAt: DateTime(2026),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final a = container.listen(squadMatchLevelsProvider('a'), (_, _) {});
        final b = container.listen(squadMatchLevelsProvider('b'), (_, _) {});
        addTearDown(a.close);
        addTearDown(b.close);
        expect(await container.read(squadMatchLevelsProvider('a').future), {
          'm': 2.5,
        });
        await container.read(squadMatchLevelsProvider('b').future);
        final target = ValueNotifier<String?>('a');
        addTearDown(target.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: ValueListenableBuilder<String?>(
                valueListenable: target,
                builder: (_, id, _) => id == null
                    ? const SizedBox()
                    : SquadStarThresholdsPage(squadId: id),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 5; i++) {
          await tester.enterText(find.byType(TextField).at(i), '${i + 1}');
        }
        await tester.ensureVisible(find.text('Zapisz'));
        await tester.tap(find.text('Zapisz'));
        await tester.pump();
        expect(repository.saves, ['a']);
        target.value = switchSquad ? 'b' : null;
        await tester.pumpAndSettle();
        repository.pending.complete();
        await tester.pumpAndSettle();
        expect(await container.read(squadMatchLevelsProvider('a').future), {
          'm': 5,
        });
        expect(
          repository.loads.where((id) => id == 'b').length,
          1,
          reason: 'Never invalidate the new squad for an old save',
        );
        expect(find.text('Zapisano progi gwiazdek.'), findsNothing);
        expect(tester.takeException(), isNull);
        // Remount and reread persisted fields, not only the success message/store.
        target.value = null;
        await tester.pumpAndSettle();
        target.value = 'a';
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          '1,0',
        );
      },
    );
  }
}
