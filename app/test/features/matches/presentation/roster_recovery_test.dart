import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/core/widgets/team_transfer_target.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/matches/application/usecases/update_match_teams_usecase.dart';
import 'package:app/features/matches/domain/exceptions/roster_edit_rejected.dart';
import 'package:app/features/matches/presentation/controllers/match_details_notifier.dart';
import 'package:app/features/matches/presentation/pages/match_details_page.dart';
import 'package:app/features/matches/presentation/widgets/match_player_tile.dart';
import '../../../fixtures/atomic_roster_backend.dart';

void main() {
  late AtomicRosterBackend backend;
  late ProviderContainer container;
  final provider = matchDetailsProvider('match');
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    backend = AtomicRosterBackend();
    backend.tables['team_players']!.removeWhere((r) => r['player_id'] == 'p0');
    backend.tables['ranking_history']!.clear();
    backend.tables['matches']!.single
      ..['tournament_id'] = 'tournament'
      ..['score_meta'] = {
        'draft_rankings': {
          for (final p in backend.tables['players']!)
            if (p['player_id'] != 'p0') p['player_id']: p['score'],
        },
      };
    backend.changeCurrentScores();
    container = ProviderContainer(
      overrides: [
        supabaseProvider.overrideWithValue(backend.client),
        authStateProvider.overrideWith(_FixtureAuth.new),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await backend.client.dispose();
  });
  UpdateMatchTeamsUseCase edits() =>
      container.read(updateMatchTeamsUseCaseProvider);
  Map<dynamic, dynamic> meta() =>
      backend.tables['matches']!.single['score_meta'] as Map;
  Future<MatchDetailsNotifier> loaded() async {
    final ready = Completer<void>();
    final sub = container.listen(provider, (_, value) {
      if (!ready.isCompleted && value.hasValue && !value.isLoading)
        ready.complete();
    }, fireImmediately: true);
    addTearDown(sub.close);
    await ready.future.timeout(const Duration(seconds: 5));
    return container.read(provider.notifier);
  }

  Future<void> submit(MatchDetailsNotifier notifier) =>
      notifier.updateTeams(['p0', 'p1'], ['p2', 'p3', 'p4']);
  void conflict() {
    backend.beforeRpc = () {
      backend.beforeRpc = null;
      for (final row in backend.tables['team_players']!) {
        if (row['player_id'] == 'p1') row['team_id'] = 'away';
        if (row['player_id'] == 'p2') row['team_id'] = 'home';
      }
      meta()['_roster_operation'] = {
        'id': 'other-operation',
        'home': ['p2'],
        'away': ['p1', 'p3', 'p4'],
        'rankings': meta()['draft_rankings'],
        'base': null,
      };
    };
  }

  for (final cancel in [false, true]) {
    test(
      'confirmed conflict -> explicit ${cancel ? 'cancel' : 'reload'} -> same membership gets new operation/base',
      () async {
        final notifier = await loaded();
        conflict();
        await submit(notifier);
        expect(container.read(provider).error, isA<RosterEditRejected>());
        final old = Map<String, dynamic>.from(backend.commands.single);
        expect((old['p_rankings'] as Map)['p0'], 90);
        backend.tables['players']!.first['score'] = 12.0;
        expect(edits().hasRejectedEdit('match'), isTrue);
        if (cancel) {
          await notifier.cancelRosterEdit();
        } else {
          await notifier.refresh();
        }
        expect(
          container
              .read(provider)
              .requireValue
              .homeTeam!
              .players
              .single
              .playerId,
          'p2',
        );
        expect(edits().hasPendingEdit('match'), isFalse);
        await submit(notifier);
        expect(container.read(provider).hasError, isFalse);
        expect(
          backend.commands.last['p_request_id'],
          isNot(old['p_request_id']),
        );
        expect(backend.commands.last['p_expected_version'], 'other-operation');
        expect((backend.commands.last['p_rankings'] as Map)['p0'], 12);
        expect(
          (old['p_rankings'] as Map)['p0'],
          90,
          reason: 'Recovery is a new operation, not a rebase of old inputs',
        );
      },
    );
  }

  test(
    'failed details reload cannot discard a confirmed rejected command',
    () async {
      final notifier = await loaded();
      conflict();
      await submit(notifier);
      final id = edits().rejectedRequestId('match');
      backend.failNextMatchRead = true;
      await notifier.refresh();
      expect(container.read(provider).hasError, isTrue);
      expect(edits().rejectedRequestId('match'), id);
      await notifier.refresh();
      expect(edits().hasPendingEdit('match'), isFalse);
      await submit(notifier);
      expect(container.read(provider).hasError, isFalse);
    },
  );

  test(
    'unknown lost reply survives reload/cancel; exact retry keeps chosen input after score drift',
    () async {
      final notifier = await loaded();
      backend.loseReply = true;
      await submit(notifier);
      expect(container.read(provider).hasError, isTrue);
      expect(edits().hasRejectedEdit('match'), isFalse);
      final command = jsonEncode(backend.commands.single);
      backend.tables['matches']!.single['home_score'] = 1;
      backend.tables['players']!.first['score'] = 12.0;
      await notifier.refresh();
      await notifier.cancelRosterEdit();
      expect(edits().hasPendingEdit('match'), isTrue);
      await expectLater(
        edits().execute(
          matchId: 'match',
          homePlayerIds: ['p1'],
          awayPlayerIds: ['p0', 'p2', 'p3', 'p4'],
        ),
        throwsStateError,
      );
      final index = backend.requests.length;
      await notifier.retryRosterEdit();
      expect(
        backend.requests[index],
        contains('/rpc/update_preserved_match_roster'),
      );
      expect(jsonEncode(backend.commands.last), command);
      expect((backend.commands.last['p_rankings'] as Map)['p0'], 90);
      expect(backend.tables['ranking_history'], isEmpty);
      expect(edits().hasPendingEdit('match'), isFalse);
      expect(container.read(provider).hasError, isFalse);
    },
  );

  test(
    'reload/cancel/discard cannot race an in-flight operation or lose its uncertain outcome',
    () async {
      final notifier = await loaded();
      final entered = Completer<void>();
      final release = Completer<void>();
      backend.loseReply = true;
      backend.waitBeforeRpc = () {
        entered.complete();
        return release.future;
      };
      final save = submit(notifier);
      await entered.future;
      await expectLater(notifier.refresh(), throwsStateError);
      await expectLater(notifier.cancelRosterEdit(), throwsStateError);
      expect(
        () => edits().discardRejected('match', requestId: 'any'),
        throwsStateError,
      );
      release.complete();
      await save;
      backend.waitBeforeRpc = null;
      final command = jsonEncode(backend.commands.single);
      await notifier.refresh();
      expect(edits().hasPendingEdit('match'), isTrue);
      await notifier.retryRosterEdit();
      expect(jsonEncode(backend.commands.last), command);
    },
  );

  test(
    'an obsolete recovery token cannot discard a newer uncertain operation',
    () async {
      final notifier = await loaded();
      conflict();
      await submit(notifier);
      final oldId = edits().rejectedRequestId('match')!;
      await notifier.refresh();
      backend.failBeforeCommit = true;
      await submit(notifier);
      final command = jsonEncode(backend.commands.last);
      edits().discardRejected('match', requestId: oldId);
      expect(edits().hasPendingEdit('match'), isTrue);
      await notifier.retryRosterEdit();
      expect(jsonEncode(backend.commands.last), command);
    },
  );

  Future<void> page(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MatchDetailsPage(squadId: 'fixture', matchId: 'match'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Akcje meczu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edytuj składy'));
    await tester.pumpAndSettle();
  }

  Future<void> move(WidgetTester tester, String id, int side) async {
    final source = find.byWidgetPredicate(
      (w) => w is MatchPlayerTile && w.player.playerId == id,
    );
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    final handle = find.descendant(
      of: source,
      matching: find.byIcon(Icons.drag_indicator),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    final target = find.byType(TeamTransferTarget).at(side);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'real match page conflict reload permits same intended roster to be saved with a new command',
    (tester) async {
      // All five are present here, so actual drag controls can express the intent.
      backend.tables['team_players']!.insert(0, {
        'match_id': 'match',
        'team_id': 'home',
        'player_id': 'p0',
      });
      (meta()['draft_rankings'] as Map)['p0'] = 41.25;
      await page(tester);
      await edit(tester);
      await move(tester, 'p1', 1);
      await move(tester, 'p2', 0);
      backend.beforeRpc = () {
        backend.beforeRpc = null;
        for (final row in backend.tables['team_players']!) {
          if (row['player_id'] == 'p0') row['team_id'] = 'away';
        }
        meta()['_roster_operation'] = {
          'id': 'widget-other',
          'home': ['p1'],
          'away': ['p0', 'p2', 'p3', 'p4'],
          'rankings': meta()['draft_rankings'],
          'base': null,
        };
      };
      await tester.tap(find.byTooltip('Zapisz'));
      await tester.pumpAndSettle();
      expect(container.read(provider).error, isA<RosterEditRejected>());
      final id = backend.commands.single['p_request_id'];
      await tester.tap(find.text('Wczytaj ponownie'));
      await tester.pumpAndSettle();
      expect(edits().hasPendingEdit('match'), isFalse);
      await edit(tester);
      await move(tester, 'p1', 1);
      await move(tester, 'p0', 0);
      await move(tester, 'p2', 0);
      await tester.tap(find.byTooltip('Zapisz'));
      await tester.pumpAndSettle();
      expect(container.read(provider).hasError, isFalse);
      expect(backend.commands.last['p_request_id'], isNot(id));
      expect(backend.commands.last['p_expected_version'], 'widget-other');
      expect((backend.commands.last['p_home'] as List).toSet(), {'p0', 'p2'});
      expect(tester.takeException(), isNull);
    },
  );

  for (final cancel in [false, true]) {
    testWidgets(
      'real page ${cancel ? 'cancel' : 'reload'} retains uncertain operation and exposes exact retry',
      (tester) async {
        await page(tester);
        backend.loseReply = true;
        await submit(container.read(provider.notifier));
        await tester.pumpAndSettle();
        final command = jsonEncode(backend.commands.single);
        await tester.tap(
          find.text(cancel ? 'Anuluj edycję składów' : 'Wczytaj ponownie'),
        );
        await tester.pumpAndSettle();
        expect(edits().hasPendingEdit('match'), isTrue);
        await tester.tap(find.byTooltip('Ponów zapis składów'));
        await tester.pumpAndSettle();
        expect(jsonEncode(backend.commands.last), command);
        expect(edits().hasPendingEdit('match'), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _FixtureAuth extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() => AsyncData(
    AuthEntity(
      accessToken: 'fixture',
      refreshToken: 'fixture',
      userId: 'owner',
      isAnonymous: false,
      email: 'owner@example.test',
    ),
  );
}
