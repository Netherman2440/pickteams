import 'dart:async';
import 'package:app/features/draft/domain/repositories/draft_experience_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:app/core/app_router.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/draft/application/create_draft_use_case.dart';
import 'package:app/features/draft/application/get_player_pair_win_rates_use_case.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/domain/entities/head_to_head_win_rate.dart';
import 'package:app/features/draft/domain/entities/stored_draft_payload.dart';
import 'package:app/features/draft/domain/repositories/draft_acceptance_repository.dart';
import 'package:app/features/draft/domain/repositories/draft_persistence_repository.dart';
import 'package:app/features/draft/domain/repositories/draft_repository.dart';
import 'package:app/features/draft/domain/repositories/draft_stats_repository.dart';
import 'package:app/features/draft/infrastructure/repositories/supabase_draft_acceptance_repository.dart';
import 'package:app/features/draft/infrastructure/repositories/supabase_draft_persistence_repository.dart';
import 'package:app/features/draft/presentation/controllers/draft_session_notifier.dart';
import 'package:app/features/draft/presentation/pages/draft_selection_page.dart';
import 'package:app/features/draft/presentation/pages/draft_results_page.dart';
import 'package:app/features/draft/presentation/controllers/draft_selection_controller.dart';
import 'package:app/features/matches/domain/repositories/match_repository.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/team.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/matches/domain/repositories/team_repository.dart';
import 'package:app/features/matches/matches_providers.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/repositories/player_repository.dart';
import 'package:app/features/players/domain/repositories/ranking_repository.dart';
import 'package:app/features/players/players_providers.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';

const ids = ['p0', 'p1', 'p2', 'p3'];
const rules = [
  DraftRule(type: DraftRuleType.together, playerIds: ['p0', 'p1']),
  DraftRule(type: DraftRuleType.against, playerIds: ['p2', 'p3']),
];

void main() {
  for (final matchId in <String?>[null, 'existing']) {
    for (final fail in [false, true]) {
      test(
        'generation/browsing writes nothing: match=$matchId error=$fail',
        () async {
          final fixture = _Fixture()..generator.fail = fail;
          final container = ProviderContainer(overrides: fixture.overrides);
          addTearDown(container.dispose);
          final notifier = container.read(
            draftSessionNotifierProvider.notifier,
          );
          await notifier.load(
            squadId: 'squad-1',
            selectedPlayerIds: ids,
            algorithm: DraftAlgorithm.combinatory,
            matchId: matchId,
          );
          expect(container.read(draftSessionNotifierProvider).hasError, fail);
          if (!fail) {
            final state = container
                .read(draftSessionNotifierProvider)
                .requireValue;
            expect(state.homeColor, matchId == null ? '#FFFFFF' : '#1E88E5');
            expect(state.awayColor, matchId == null ? '#000000' : '#E53935');
            if (matchId != null) {
              verify(
                () => fixture.matches.getMatch(matchId: 'existing'),
              ).called(1);
              verify(() => fixture.teams.getMatchTeams('existing')).called(1);
            }
          }
          notifier.selectProposal(1);
          if (!fail) {
            notifier.movePlayer(playerId: 'p0', toHome: false);
            final changed = container
                .read(draftSessionNotifierProvider)
                .requireValue;
            expect(changed.homeColor, matchId == null ? '#FFFFFF' : '#1E88E5');
            expect(changed.awayColor, matchId == null ? '#000000' : '#E53935');
          }
          notifier.cancelLoad();
          fixture.expectNoWrites();
        },
      );
    }
  }

  test(
    'redraw color read failure does not expose an accept-ready default preview',
    () async {
      final fixture = _Fixture();
      when(
        () => fixture.matches.getMatch(matchId: 'existing'),
      ).thenThrow(StateError('color read failed'));
      final container = ProviderContainer(overrides: fixture.overrides);
      addTearDown(container.dispose);
      await container
          .read(draftSessionNotifierProvider.notifier)
          .load(
            squadId: 'squad-1',
            selectedPlayerIds: ids,
            algorithm: DraftAlgorithm.combinatory,
            matchId: 'existing',
          );
      expect(container.read(draftSessionNotifierProvider).hasError, isTrue);
      verify(() => fixture.matches.getMatch(matchId: 'existing')).called(1);
      fixture.expectNoWrites();
    },
  );

  test('stored proposal lookup is read-only and does not regenerate', () async {
    final fixture = _Fixture();
    when(
      () => fixture.persistence.getMatchDraft(matchId: 'existing'),
    ).thenAnswer(
      (_) async => const StoredDraftPayload(
        draftId: 'draft',
        matchId: 'existing',
        teamCount: 2,
        proposalsCount: 1,
        seed: null,
        errorMessage: null,
        status: 'completed',
        proposals: [
          StoredDraftProposal(
            teams: [
              ['p0', 'p1'],
              ['p2', 'p3'],
            ],
          ),
        ],
        winRateMatrix: {},
      ),
    );
    final container = ProviderContainer(overrides: fixture.overrides);
    addTearDown(container.dispose);
    await container
        .read(draftSessionNotifierProvider.notifier)
        .load(
          squadId: 'squad-1',
          selectedPlayerIds: [],
          algorithm: DraftAlgorithm.combinatory,
          matchId: 'existing',
        );
    expect(
      container.read(draftSessionNotifierProvider).requireValue.proposals,
      hasLength(1),
    );
    final state = container.read(draftSessionNotifierProvider).requireValue;
    expect(state.homeColor, '#1E88E5');
    expect(state.awayColor, '#E53935');
    verify(() => fixture.matches.getMatch(matchId: 'existing')).called(1);
    verify(() => fixture.teams.getMatchTeams('existing')).called(1);
    expect(fixture.generator.calls, 0);
    verify(
      () => fixture.persistence.getMatchDraft(matchId: 'existing'),
    ).called(1);
    verifyNoMoreInteractions(fixture.persistence);
    fixture.expectNoWrites(checkPersistence: false);
  });

  for (final relations in [false, true]) {
    for (final systemBack in [false, true]) {
      testWidgets(
        'real routes: relations=$relations systemBack=$systemBack retain selection then exit to squad without writes',
        (tester) async {
          final fixture = _Fixture();
          final router = await fixture.mount(tester, relations: relations);
          await tester.tap(
            find.text(relations ? 'Wygeneruj propozycje' : 'Wygeneruj'),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DraftResultsPage), findsOneWidget);
          expect(
            router.routeInformationProvider.value.uri.path,
            '/squads/squad-1/matches/preview',
          );
          expect(fixture.generator.lastSubstitute, isFalse);
          if (relations) {
            expect(
              fixture.generator.lastRules.map((r) => r.type),
              rules.map((r) => r.type),
            );
          }
          final container = ProviderScope.containerOf(
            tester.element(find.byType(DraftResultsPage)),
          );
          container
              .read(draftSessionNotifierProvider.notifier)
              .selectProposal(1);
          await tester.pump();
          expect(find.text('Propozycja 2 z 2'), findsOneWidget);
          if (systemBack) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.byTooltip('Wstecz'));
          }
          await tester.pumpAndSettle();
          final selection = tester.widget<DraftSelectionPage>(
            find.byType(DraftSelectionPage),
          );
          expect(selection.initialSelectedIds, unorderedEquals(ids));
          expect(selection.playWithSubstitute, isFalse);
          if (relations) {
            expect(
              selection.initialDraftRules.map((r) => r.type),
              rules.map((r) => r.type),
            );
            expect(
              container
                  .read(draftSelectionControllerProvider)
                  .requireValue
                  .draftRules
                  .map((r) => r.type),
              rules.map((r) => r.type),
            );
          }
          expect(
            container
                .read(draftSelectionControllerProvider)
                .requireValue
                .selectedPlayerIds,
            unorderedEquals(ids),
          );
          fixture.expectNoWrites();
          // Results replaces the stack with selection. System Back must still
          // be handled, with this squad as the real page below selection.
          tester.testTextInput.hide();
          expect(await tester.binding.handlePopRoute(), isTrue);
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            '/squads/squad-1',
          );
          fixture.expectNoWrites();
          await tester.pumpWidget(const SizedBox());
          router.dispose();
        },
      );
    }
  }

  testWidgets(
    'departure during generation ignores late result and performs no writes',
    (tester) async {
      final fixture = _Fixture();
      fixture.generator.gate = Completer<void>();
      final router = await fixture.mount(tester);
      await tester.tap(find.text('Wygeneruj'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(DraftResultsPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      fixture.generator.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DraftSelectionPage), findsOneWidget);
      fixture.expectNoWrites();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'accept awaits RPC, blocks double click, leaves preview on error and retries before navigation',
    (tester) async {
      final fixture = _Fixture();
      final router = await fixture.mount(tester);
      await tester.tap(find.text('Wygeneruj'));
      await tester.pumpAndSettle();
      final accept = find.text('Zakceptuj propozycję');
      await tester.tap(accept);
      await tester.tap(accept);
      await tester.pump();
      expect(fixture.acceptance.calls, 1);
      expect(find.byType(DraftResultsPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(DraftResultsPage), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/squads/squad-1/matches/preview',
      );
      expect(fixture.acceptance.payload!['proposals'], hasLength(2));
      final request = fixture.acceptance.requestId;
      fixture.acceptance.reply.completeError(
        StateError('transaction rejected'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DraftResultsPage), findsOneWidget);
      expect(find.textContaining('Ponów akceptację'), findsOneWidget);
      fixture.acceptance.reply = Completer<String>();
      await tester.tap(accept);
      await tester.pump();
      expect(fixture.acceptance.calls, 2);
      expect(fixture.acceptance.requestId, request);
      fixture.acceptance.reply.complete('accepted');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/squads/squad-1/matches/accepted',
      );
      verifyZeroInteractions(fixture.teams);
      verifyZeroInteractions(fixture.ranking);
      verifyZeroInteractions(fixture.persistence);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}

class _Fixture {
  final players = _Players();
  final matches = _Matches();
  final teams = _Teams();
  final ranking = _Ranking();
  final persistence = _Persistence();
  final generator = _Generator();
  final acceptance = _Acceptance();
  _Fixture() {
    when(() => players.getSquadPlayers(squadId: 'squad-1')).thenAnswer(
      (_) async => [
        for (var i = 0; i < 4; i++)
          Player(
            playerId: ids[i],
            squadId: 'squad-1',
            name: 'Player $i',
            baseRanking: 40,
            ranking: 40,
            createdAt: DateTime(2026),
          ),
      ],
    );
    when(() => matches.getMatch(matchId: 'existing')).thenAnswer(
      (_) async => Match(
        matchId: 'existing',
        squadId: 'squad-1',
        createdAt: DateTime(2026),
        homeTeam: const Team(
          teamId: 'h',
          matchId: 'existing',
          side: Side.home,
          color: '#1E88E5',
        ),
        awayTeam: const Team(
          teamId: 'a',
          matchId: 'existing',
          side: Side.away,
          color: '#E53935',
        ),
      ),
    );
    when(() => teams.getMatchTeams('existing')).thenAnswer(
      (_) async => const [
        Team(
          teamId: 'h',
          matchId: 'existing',
          side: Side.home,
          color: '#1E88E5',
        ),
        Team(
          teamId: 'a',
          matchId: 'existing',
          side: Side.away,
          color: '#E53935',
        ),
      ],
    );
    when(
      () => matches.getMatch(matchId: 'accepted'),
    ).thenThrow(StateError('fixture detail boundary'));
  }
  List<Override> get overrides => [
    playerRepositoryProvider.overrideWithValue(players),
    matchRepositoryProvider.overrideWithValue(matches),
    teamRepositoryProvider.overrideWithValue(teams),
    rankingRepositoryProvider.overrideWithValue(ranking),
    draftPersistenceRepositoryProvider.overrideWithValue(persistence),
    draftAcceptanceRepositoryProvider.overrideWithValue(acceptance),
    combinatoryCreateDraftUseCaseProvider.overrideWithValue(
      CreateDraftUseCase(generator, experienceRepository: _Experience()),
    ),
    greedyCreateDraftUseCaseProvider.overrideWithValue(
      CreateDraftUseCase(generator, experienceRepository: _Experience()),
    ),
    getPlayerPairWinRatesUseCaseProvider.overrideWithValue(
      GetPlayerPairWinRatesUseCase(_Stats()),
    ),
    authStateProvider.overrideWith(_Auth.new),
    squadDetailProvider.overrideWith(
      (ref, id) async => throw StateError('fixture shell title'),
    ),
  ];
  Future<GoRouter> mount(WidgetTester tester, {bool relations = false}) async {
    final router = GoRouter(
      routes: appRouter.configuration.routes,
      initialLocation: relations
          ? '/squads/squad-1/matches/relations/against'
          : '/squads/squad-1/matches/draft',
      initialExtra: {
        'selectedIds': ids,
        'playWithSubstitute': false,
        if (relations)
          'draftRules': [
            for (final rule in rules)
              {'type': rule.type.name, 'playerIds': rule.playerIds},
          ],
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  void expectNoWrites({bool checkPersistence = true}) {
    verifyNoMoreInteractions(matches);
    verifyNoMoreInteractions(teams);
    verifyZeroInteractions(ranking);
    if (checkPersistence) verifyZeroInteractions(persistence);
    expect(acceptance.calls, 0);
  }
}

class _Auth extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() => const AsyncData(null);
}

class _Players extends Mock implements PlayerRepository {}

class _Matches extends Mock implements MatchRepository {}

class _Teams extends Mock implements TeamRepository {}

class _Ranking extends Mock implements RankingRepository {}

class _Persistence extends Mock implements DraftPersistenceRepository {}

class _Experience implements DraftExperienceRepository {
  @override
  Future<Map<String, int>> getAppearances({
    required List<String> playerIds,
    String? currentMatchId,
  }) async => {for (final id in playerIds) id: 0};
}

class _Stats implements DraftStatsRepository {
  @override
  Future<List<HeadToHeadWinRate>> getPlayerPairWinRates({
    required List<String> playerIds,
  }) async => [];
}

class _Generator implements DraftRepository {
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  List<DraftRule> lastRules = [];
  bool? lastSubstitute;
  @override
  Future<List<Draft>> createDraft({
    required List<Player> players,
    int teamCount = 2,
    List<DraftRule> rules = const [],
    int limit = 20,
    bool playWithSubstitute = true,
    int? seed,
    Map<String, int> appearances = const {},
  }) async {
    calls++;
    lastRules = rules;
    lastSubstitute = playWithSubstitute;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('generation failed');
    return [
      for (var i = 0; i < 2; i++)
        Draft.twoTeams(
          homePlayers: [players[0], players[1 + i]],
          awayPlayers: [players[2 - i], players[3]],
          homeTotalRanking: 80,
          awayTotalRanking: 80,
        ),
    ];
  }
}

class _Acceptance implements DraftAcceptanceRepository {
  int calls = 0;
  String? requestId;
  Map<String, dynamic>? payload;
  Completer<String> reply = Completer<String>();
  @override
  Future<String> accept({
    required String requestId,
    required String squadId,
    String? matchId,
    required Map<String, dynamic> payload,
  }) {
    calls++;
    this.requestId = requestId;
    this.payload = payload;
    return reply.future;
  }
}
