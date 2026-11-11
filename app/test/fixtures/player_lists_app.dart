// Credential-free render harness. All state lives in this process.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/app_theme.dart';
import 'package:app/core/root_shell.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/draft/domain/repositories/draft_acceptance_repository.dart';
import 'package:app/features/draft/infrastructure/repositories/supabase_draft_acceptance_repository.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/presentation/controllers/draft_session_notifier.dart';
import 'package:app/features/draft/presentation/pages/draft_results_page.dart';
import 'package:app/features/draft/presentation/pages/draft_selection_page.dart';
import 'package:app/features/draft/presentation/state/draft_session_state.dart';
import 'package:app/features/matches/application/dto/match_details_dto.dart';
import 'package:app/features/matches/application/dto/player_dto.dart';
import 'package:app/features/matches/application/dto/team_dto.dart';
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
  int acceptances = 0;
  int deletions = 0;
  int rematches = 0;
  Object? draftExtra;
}

class PlayerListsFixture extends StatefulWidget {
  const PlayerListsFixture({
    super.key,
    this.page = 'match',
    this.role = SquadRole.owner,
    this.writes,
    this.match,
    this.textScale,
    this.systemPadding,
  });
  final String page;
  final SquadRole role;
  final FixtureWrites? writes;
  final MatchDetailsDto? match;
  final double? textScale;
  final EdgeInsets? systemPadding;
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
            builder: (_, state) {
              widget.writes?.draftExtra = state.extra;
              final extra = state.extra as Map<String, dynamic>?;
              return DraftSelectionPage(
                squadId: 'fixture',
                initialSelectedIds:
                    extra?['selectedIds'] as List<String>? ??
                    fixturePlayers.take(16).map((p) => p.playerId).toList(),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/matches/draft',
            name: 'draftSelection',
            builder: (_, state) => DraftSelectionPage(
              squadId: 'fixture',
              initialSelectedIds:
                  (state.extra as Map<String, dynamic>?)?['selectedIds']
                      as List<String>?,
            ),
          ),
          GoRoute(
            path: '/squads/:squadId/matches/preview',
            name: 'draftPreview',
            builder: (_, _) => _results(),
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
      matchDetailsProvider.overrideWith(
        () => FixtureMatch(initial: widget.match, writes: widget.writes),
      ),
      draftAcceptanceRepositoryProvider.overrideWithValue(
        _FixtureAcceptance(widget.writes),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: widget.textScale == null
              ? null
              : TextScaler.linear(widget.textScale!),
          padding: widget.systemPadding,
          viewPadding: widget.systemPadding,
        ),
        child: child!,
      ),
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
  String? tournamentId,
  bool withoutTeams = false,
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
    tournamentId: tournamentId,
    homeScore: homeScore,
    awayScore: awayScore,
    homeWinProbability: .52,
    homeTeam: withoutTeams
        ? null
        : team(
            'home',
            'Niebiescy',
            '#1E88E5',
            homeIds ?? fixturePlayers.take(8).map((p) => p.playerId).toList(),
          ),
    awayTeam: withoutTeams
        ? null
        : team(
            'away',
            'Czerwoni',
            '#E53935',
            awayIds ??
                fixturePlayers.skip(8).take(8).map((p) => p.playerId).toList(),
          ),
  );
}

class FixtureMatch extends MatchDetailsNotifier {
  FixtureMatch({this.initial, this.writes});
  final MatchDetailsDto? initial;
  final FixtureWrites? writes;

  @override
  AsyncValue<MatchDetailsDto> build(String matchId) =>
      AsyncData(initial ?? fixtureMatch());
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
  Future<MatchDetailsDto> rematch() async {
    if (writes != null) writes!.rematches++;
    return fixtureMatch();
  }

  @override
  Future<void> deleteMatch() async {
    if (writes != null) writes!.deletions++;
  }
}

class _FixtureAcceptance implements DraftAcceptanceRepository {
  _FixtureAcceptance(this.writes);
  final FixtureWrites? writes;

  @override
  Future<String> accept({
    required String requestId,
    required String squadId,
    String? matchId,
    required Map<String, dynamic> payload,
  }) async {
    if (writes != null) writes!.acceptances++;
    writes?.homeIds = (payload['home'] as List).cast<String>();
    writes?.awayIds = (payload['away'] as List).cast<String>();
    return matchId ?? 'match';
  }
}
