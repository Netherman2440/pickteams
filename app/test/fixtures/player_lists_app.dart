// Credential-free render harness. All state lives in this process.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/app_theme.dart';
import 'package:app/core/root_shell.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/draft/application/save_match_draft_use_case.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/domain/repositories/draft_persistence_repository.dart';
import 'package:app/features/draft/presentation/controllers/draft_session_notifier.dart';
import 'package:app/features/draft/presentation/pages/draft_results_page.dart';
import 'package:app/features/draft/presentation/pages/draft_selection_page.dart';
import 'package:app/features/draft/presentation/state/draft_session_state.dart';
import 'package:app/features/matches/application/dto/match_details_dto.dart';
import 'package:app/features/matches/application/dto/player_dto.dart';
import 'package:app/features/matches/application/dto/team_dto.dart';
import 'package:app/features/matches/presentation/controllers/create_match_controller.dart';
import 'package:app/features/matches/presentation/controllers/match_details_notifier.dart';
import 'package:app/features/matches/presentation/pages/match_details_page.dart';
import 'package:app/features/players/application/usecases/get_squad_players_usecase.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/repositories/player_repository.dart';
import 'package:app/features/squads/domain/entities/squad.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';

final fixturePlayers = [
  for (final (i, name) in [
    'Michał Kowalski',
    'Łukasz Wiśniewski',
    'Paweł Zieliński',
    'Krzysztof Wójcik',
    'Tomasz Kamiński',
    'Jakub Lewandowski',
    'Piotr Nowak',
    'Bartosz Mazur',
    'Adam Dąbrowski',
    'Marcin Kaczmarek',
    'Mateusz Szymański',
    'Rafał Woźniak',
    'Wojciech Kozłowski',
    'Grzegorz Jankowski',
    'Marek Wojciechowski',
    'Andrzej Wróbel',
    'Jan Krawczyk',
    'Robert Zając',
    'Dawid Król',
    'Filip Wieczorek',
    'Karol Jabłoński',
    'Szymon Nowakowski',
  ].indexed)
    Player(
      playerId: 'p$i',
      squadId: 'fixture',
      name: name,
      baseRanking: 50,
      ranking: 60.25 - i / 2,
      createdAt: DateTime(2026, 1, 1),
    ),
];

class FixtureWrites {
  List<String> homeIds = [];
  List<String> awayIds = [];
}

class PlayerListsFixture extends StatefulWidget {
  const PlayerListsFixture({
    super.key,
    this.page = 'match',
    this.role = SquadRole.owner,
    this.writes,
  });
  final String page;
  final SquadRole role;
  final FixtureWrites? writes;
  @override
  State<PlayerListsFixture> createState() => _PlayerListsFixtureState();
}

class _PlayerListsFixtureState extends State<PlayerListsFixture> {
  late final GoRouter router = GoRouter(
    initialLocation: '/squads/fixture/${widget.page}',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            RootShell(location: state.uri.toString(), child: child),
        routes: [
          GoRoute(
            path: '/squads/:squadId/selection',
            name: 'draftCreate',
            builder: (_, _) => DraftSelectionPage(
              squadId: 'fixture',
              initialSelectedIds: fixturePlayers
                  .take(16)
                  .map((p) => p.playerId)
                  .toList(),
            ),
          ),
          GoRoute(
            path: '/squads/:squadId/results',
            name: 'draftRelations',
            builder: (_, _) => _results(),
          ),
          GoRoute(
            path: '/squads/:squadId/matches/:matchId/draft',
            name: 'matchDraft',
            builder: (_, _) => _results(),
          ),
          GoRoute(
            path: '/squads/:squadId/match',
            name: 'matches',
            builder: (_, _) =>
                const MatchDetailsPage(squadId: 'fixture', matchId: 'match'),
          ),
          GoRoute(
            path: '/squads/:squadId/matches/:matchId',
            name: 'matchDetails',
            builder: (_, _) =>
                const MatchDetailsPage(squadId: 'fixture', matchId: 'match'),
          ),
          GoRoute(
            path: '/squads/:squadId/players/:playerId',
            name: 'playerDetails',
            builder: (_, state) => Scaffold(
              appBar: AppBar(title: const Text('Fake player destination')),
              body: Text(state.pathParameters['playerId']!),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _results() => DraftResultsPage(
    squadId: 'fixture',
    matchId: 'match',
    selectedPlayerIds: fixturePlayers.take(16).map((p) => p.playerId).toList(),
  );

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      authStateProvider.overrideWith(_FixtureAuth.new),
      squadDetailProvider.overrideWith(
        (ref, id) async => Squad(
          squadId: id,
          ownerId: 'fixture',
          name: 'Przykładowy skład',
          visibility: SquadVisibility.private,
          sportType: SportType.football,
          createdAt: DateTime(2026, 1, 1),
          role: widget.role,
        ),
      ),
      getSquadPlayersUseCaseProvider.overrideWithValue(
        GetSquadPlayersUseCase(_FixturePlayers()),
      ),
      draftSessionNotifierProvider.overrideWith(_FixtureDraft.new),
      matchDetailsProvider.overrideWith(FixtureMatch.new),
      createMatchControllerProvider.overrideWith(
        () => _FixtureCreate(widget.writes),
      ),
      saveMatchDraftUseCaseProvider.overrideWithValue(
        SaveMatchDraftUseCase(_FixturePersistence()),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    ),
  );
}

class _FixtureAuth extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() => AsyncData(
    AuthEntity(
      accessToken: '',
      refreshToken: '',
      userId: 'fixture',
      isAnonymous: false,
      email: 'fixture@example.invalid',
    ),
  );
}

class _FixturePlayers implements PlayerRepository {
  @override
  Future<List<Player>> getSquadPlayers({required String squadId}) async =>
      fixturePlayers;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Fixture: ${invocation.memberName}');
}

class _FixtureDraft extends DraftSessionNotifier {
  @override
  Future<void> load({
    required String squadId,
    required List<String> selectedPlayerIds,
    required DraftAlgorithm algorithm,
    List<DraftRule> rules = const [],
    String? matchId,
    bool playWithSubstitute = true,
  }) async {
    final home = fixturePlayers.take(8).toList();
    final away = fixturePlayers.skip(8).take(8).toList();
    state = AsyncData(
      DraftSessionState(
        proposals: [
          Draft.twoTeams(
            homePlayers: home,
            awayPlayers: away,
            homeTotalRanking: 466,
            awayTotalRanking: 434,
          ),
          Draft.twoTeams(
            homePlayers: away,
            awayPlayers: home,
            homeTotalRanking: 434,
            awayTotalRanking: 466,
          ),
        ],
        selectedIndex: 0,
        seed: 1,
        home: home,
        away: away,
        winRateMatrix: const {},
        homeWinProbability: .52,
      ),
    );
  }
}

MatchDetailsDto fixtureMatch({
  int? homeScore,
  int? awayScore,
  List<String>? homeIds,
  List<String>? awayIds,
}) {
  TeamDto team(String id, String name, String color, List<String> ids) =>
      TeamDto(
        teamId: id,
        matchId: 'match',
        name: name,
        color: color,
        players: [
          for (final id in ids)
            PlayerDto(
              playerId: id,
              name: fixturePlayers.firstWhere((p) => p.playerId == id).name,
              // Snapshot differs from today's ranking in the selection fixture.
              ranking:
                  fixturePlayers.firstWhere((p) => p.playerId == id).ranking -
                  10.125,
            ),
        ],
      );
  return MatchDetailsDto(
    matchId: 'match',
    squadId: 'fixture',
    createdAt: DateTime(2026, 11, 10, 18),
    homeScore: homeScore,
    awayScore: awayScore,
    homeWinProbability: .52,
    homeTeam: team(
      'home',
      'Niebiescy',
      '#1E88E5',
      homeIds ?? fixturePlayers.take(8).map((p) => p.playerId).toList(),
    ),
    awayTeam: team(
      'away',
      'Czerwoni',
      '#E53935',
      awayIds ?? fixturePlayers.skip(8).take(8).map((p) => p.playerId).toList(),
    ),
  );
}

class FixtureMatch extends MatchDetailsNotifier {
  @override
  AsyncValue<MatchDetailsDto> build(String matchId) =>
      AsyncData(fixtureMatch());
  @override
  Future<void> updateScore(String squadId, int homeScore, int awayScore) async {
    state = AsyncData(fixtureMatch(homeScore: homeScore, awayScore: awayScore));
  }

  @override
  Future<void> updateTeams(
    List<String> homePlayerIds,
    List<String> awayPlayerIds,
  ) async {
    state = AsyncData(
      fixtureMatch(homeIds: homePlayerIds, awayIds: awayPlayerIds),
    );
  }

  @override
  Future<void> updateTeamsMeta({
    required String homeTeamId,
    required String awayTeamId,
    String? homeName,
    String? homeColor,
    String? awayName,
    String? awayColor,
  }) async {}
  @override
  Future<MatchDetailsDto> rematch() async => fixtureMatch();
  @override
  Future<void> deleteMatch() async {}
}

class _FixtureCreate extends CreateMatchController {
  _FixtureCreate(this.writes);
  final FixtureWrites? writes;

  MatchDetailsDto _accept(List<Player> home, List<Player> away) {
    writes?.homeIds = home.map((p) => p.playerId).toList();
    writes?.awayIds = away.map((p) => p.playerId).toList();
    return fixtureMatch();
  }

  @override
  Future<MatchDetailsDto?> createMatch({
    required String squadId,
    required List<Player> homePlayers,
    required List<Player> awayPlayers,
    List<String> rankingHistoryPlayerIds = const [],
    String? homeTeamName,
    String? awayTeamName,
  }) async => _accept(homePlayers, awayPlayers);
  @override
  Future<MatchDetailsDto?> updateMatch({
    required String matchId,
    required List<Player> homePlayers,
    required List<Player> awayPlayers,
  }) async => _accept(homePlayers, awayPlayers);
}

class _FixturePersistence implements DraftPersistenceRepository {
  @override
  Future<void> upsertCompletedDraft({
    required String squadId,
    required String matchId,
    required List<Draft> proposals,
    required Map<String, Map<String, double>> winRateMatrix,
    required int teamCount,
    int? seed,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Fixture: ${invocation.memberName}');
}
