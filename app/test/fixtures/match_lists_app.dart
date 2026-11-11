// Offline fixture for the real squad and player match lists. No service setup.
import 'package:app/core/app_theme.dart';
import 'package:app/core/root_shell.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/matches/domain/entities/team.dart';
import 'package:app/features/matches/presentation/controllers/squad_matches_notifier.dart';
import 'package:app/features/matches/presentation/pages/squad_matches_page.dart';
import 'package:app/features/players/presentation/pages/player_matches_page.dart';
import 'package:app/features/players/presentation/state/player_matches_provider.dart';
import 'package:app/features/players/presentation/state/player_name_provider.dart';
import 'package:app/features/squads/domain/entities/squad.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

Match sampleMatch({
  String id = 'original-match',
  String home = 'Gospodarze',
  String away = 'Goście',
  int? homeScore = 14,
  int? awayScore = 5,
  bool empty = false,
}) => Match(
  matchId: id,
  squadId: 'original-squad',
  createdAt: DateTime(2026, 1, 2, 18),
  homeScore: homeScore,
  awayScore: awayScore,
  homeTeam: Team(
    teamId: 'home-$id',
    matchId: id,
    side: Side.home,
    name: home,
    color: '#E57373',
    playerCount: empty ? 0 : 8,
  ),
  awayTeam: Team(
    teamId: 'away-$id',
    matchId: id,
    side: Side.away,
    name: away,
    color: '#64B5F6',
    playerCount: empty ? 0 : 8,
  ),
);

final sampleMatches = [
  sampleMatch(),
  sampleMatch(id: 'reverse', homeScore: 8, awayScore: 16),
  sampleMatch(id: 'zero', homeScore: 0, awayScore: 2),
  sampleMatch(id: 'draw', homeScore: 0, awayScore: 0),
  sampleMatch(id: 'long-score', homeScore: 12345, awayScore: 67890),
  sampleMatch(id: 'partial', homeScore: 8, awayScore: null),
  sampleMatch(
    id: 'long',
    home: 'Przykładowi gospodarze z północnej dzielnicy',
    away: 'Przykładowi goście z południowej dzielnicy',
    homeScore: 8,
    awayScore: 16,
  ),
  sampleMatch(id: 'pending', homeScore: null, awayScore: null),
  sampleMatch(
    id: 'empty',
    home: ' ',
    away: '',
    homeScore: null,
    awayScore: null,
    empty: true,
  ),
];

class MatchListsFixture extends StatefulWidget {
  const MatchListsFixture({
    super.key,
    this.player = false,
    this.matches,
    this.textScale = 1,
    this.androidInsets = false,
    this.contentWidth,
    this.fail = false,
  });
  final bool player;
  final bool fail;
  final List<Match>? matches;
  final double textScale;
  final bool androidInsets;
  final double? contentWidth;

  @override
  State<MatchListsFixture> createState() => _MatchListsFixtureState();
}

class _MatchListsFixtureState extends State<MatchListsFixture> {
  late final router = GoRouter(
    initialLocation: widget.player
        ? '/squads/original-squad/players/fake-player/matches'
        : '/squads/original-squad/matches',
    routes: [
      ShellRoute(
        builder: (_, state, child) => RootShell(
          location: state.uri.toString(),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: widget.contentWidth, child: child),
          ),
        ),
        routes: [
          GoRoute(
            path: '/squads/:squadId/matches',
            builder: (_, state) =>
                SquadMatchesPage(squadId: state.pathParameters['squadId']!),
          ),
          GoRoute(
            path: '/squads/:squadId/players/:playerId/matches',
            builder: (_, state) => PlayerMatchesPage(
              squadId: state.pathParameters['squadId']!,
              playerId: state.pathParameters['playerId']!,
            ),
          ),
          GoRoute(
            path: '/squads/:squadId/matches/:matchId',
            name: 'matchDetails',
            builder: (_, state) => Scaffold(
              appBar: AppBar(title: const Text('Fake match destination')),
              body: Text(
                'route: ${state.pathParameters['squadId']}/${state.pathParameters['matchId']}',
              ),
            ),
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      authStateProvider.overrideWith(_FakeAuth.new),
      squadDetailProvider.overrideWith(
        (ref, id) async => Squad(
          squadId: id,
          ownerId: 'fake-owner',
          name: 'Dane przykładowe',
          visibility: SquadVisibility.private,
          sportType: SportType.football,
          createdAt: DateTime(2026, 1, 1),
          role: SquadRole.member,
        ),
      ),
      squadMatchesProvider.overrideWith(
        () => _FakeMatches(widget.matches ?? sampleMatches, widget.fail),
      ),
      playerMatchesProvider.overrideWith((ref, id) async {
        if (widget.fail) throw StateError('Offline fixture failure');
        return widget.matches ?? sampleMatches;
      }),
      playerNameProvider.overrideWith((ref, id) async => 'Gracz przykładowy'),
    ],
    child: MaterialApp.router(
      theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.android),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(widget.textScale),
          padding: widget.androidInsets
              ? const EdgeInsets.only(top: 24, bottom: 24)
              : null,
          viewPadding: widget.androidInsets
              ? const EdgeInsets.only(top: 24, bottom: 24)
              : null,
        ),
        child: child!,
      ),
    ),
  );
}

class _FakeMatches extends SquadMatchesNotifier {
  _FakeMatches(this.matches, this.fail);
  final List<Match> matches;
  final bool fail;
  @override
  AsyncValue<List<Match>> build(String squadId) => fail
      ? AsyncError(StateError('Offline fixture failure'), StackTrace.current)
      : AsyncData(matches);
  @override
  Future<void> refresh() async {}
}

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() => AsyncData(
    AuthEntity(
      accessToken: '',
      refreshToken: '',
      userId: 'fake-owner',
      email: 'fixture@example.invalid',
      isAnonymous: false,
    ),
  );
}
