// Credential-free synthetic data for issue 79. Only presentation providers are
// replaced. The fixture mounts the production pages and production comparators.
import 'package:app/core/app_theme.dart';
import 'package:app/features/matches/application/match_level_providers.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/matches/domain/entities/team.dart';
import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/entities/player_head_to_head_stat.dart';
import 'package:app/features/players/domain/entities/player_stats.dart';
import 'package:app/features/players/domain/entities/ranking_history_entry.dart';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/presentation/controllers/player_details_controller.dart';
import 'package:app/features/players/presentation/pages/player_details_page.dart';
import 'package:app/features/players/presentation/pages/player_matches_page.dart';
import 'package:app/features/players/presentation/pages/player_stats_page.dart';
import 'package:app/features/players/presentation/pages/player_tournaments_page.dart';
import 'package:app/features/players/presentation/state/player_matches_provider.dart';
import 'package:app/features/players/presentation/state/player_name_provider.dart';
import 'package:app/features/players/presentation/state/player_stats_provider.dart';
import 'package:app/features/players/presentation/state/player_tournaments_provider.dart';
import 'package:app/features/squads/domain/entities/squad.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:app/features/tournaments/domain/entities/tournament.dart';
import 'package:app/features/tournaments/domain/entities/tournament_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const profileGames = [
  (true, 4, 0, 69.4),
  (false, 2, 3, 68.9),
  (true, 3, 1, 69.8),
  (false, 4, 2, 70.4),
  (true, 2, 1, 70.9),
  (false, 1, 4, 70.1),
  (true, 4, 1, 71.2),
  (false, 3, 3, 71.2),
  (true, 3, 2, 71.8),
  (true, 5, 1, 72.5),
  (false, 4, 1, 73.3),
  (true, 2, 0, 73.8),
  (false, 4, 2, 74.1),
  (true, 5, 2, 74.6),
];

class PlayerProfileFixture extends StatefulWidget {
  const PlayerProfileFixture({
    super.key,
    this.initialSection = '',
    this.count = 14,
    this.longName = false,
    this.dark = true,
  });
  final String initialSection;
  final int count;
  final bool longName;
  final bool dark;
  @override
  State<PlayerProfileFixture> createState() => _PlayerProfileFixtureState();
}

class _PlayerProfileFixtureState extends State<PlayerProfileFixture> {
  late bool dark = widget.dark;
  late final games = profileGames.take(widget.count).toList();
  late final name = widget.longName
      ? 'Michał Aleksander Krawiec-Wiśniewski o bardzo długim nazwisku'
      : 'Michał Krawiec';
  late final router = GoRouter(
    initialLocation: '/squads/demo/players/player${widget.initialSection}',
    routes: [
      GoRoute(
        path: '/squads/:squadId/players/:playerId',
        name: 'playerDetails',
        builder: (_, _) =>
            const PlayerDetailsPage(squadId: 'demo', playerId: 'player'),
      ),
      GoRoute(
        path: '/squads/:squadId/players/:playerId/stats',
        name: 'playerStats',
        builder: (_, _) =>
            const PlayerStatsPage(squadId: 'demo', playerId: 'player'),
      ),
      GoRoute(
        path: '/squads/:squadId/players/:playerId/matches',
        name: 'playerMatches',
        builder: (_, _) =>
            const PlayerMatchesPage(squadId: 'demo', playerId: 'player'),
      ),
      GoRoute(
        path: '/squads/:squadId/players/:playerId/tournaments',
        name: 'playerTournaments',
        builder: (_, _) =>
            const PlayerTournamentsPage(squadId: 'demo', playerId: 'player'),
      ),
      GoRoute(
        path: '/squads/:squadId/matches/:matchId',
        name: 'matchDetails',
        builder: (_, state) => Scaffold(
          appBar: AppBar(
            title: Text('Mecz ${state.pathParameters['matchId']}'),
          ),
          body: const Text(
            'Synthetic destination; match editor covered by regression fixture.',
          ),
        ),
      ),
      GoRoute(
        path: '/squads/:squadId/tournaments/:tournamentId',
        name: 'tournamentDetails',
        builder: (_, state) => Scaffold(
          appBar: AppBar(title: const Text('Turniej demonstracyjny')),
          body: const Text('Synthetic tournament destination.'),
        ),
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
      playerNameProvider.overrideWith((ref, id) async => name),
      playerDetailsProvider.overrideWith(
        (ref, id) async => PlayerDetailsState(
          player: Player(
            playerId: id,
            squadId: 'demo',
            name: name,
            ranking: games.isEmpty ? 69 : games.last.$4,
            baseRanking: 69,
            position: 'midfielder',
            createdAt: DateTime(2026),
          ),
          rankingHistory: [
            for (final (i, g) in games.indexed)
              RankingHistoryEntry(
                rankingHistoryId: 'h$i',
                playerId: id,
                matchId: '${i + 1}',
                ranking: i == 0 ? 69 : games[i - 1].$4,
                change: g.$4 - (i == 0 ? 69 : games[i - 1].$4),
                createdAt: DateTime(2026, 9, 3 + 6 * i),
              ),
          ],
        ),
      ),
      squadDetailProvider.overrideWith(
        (ref, id) async => Squad(
          squadId: id,
          ownerId: 'demo',
          name: 'Skład demonstracyjny',
          visibility: SquadVisibility.public,
          sportType: SportType.football,
          role: SquadRole.member,
          createdAt: DateTime(2026),
        ),
      ),
      squadGoalHistoryProvider.overrideWith(
        (ref, id) async => [
          for (final g in games)
            GoalComparisonMatch(
              home: GoalComparisonTeam(
                color: 'ffffff',
                playerIds: g.$1 ? ['player'] : ['other'],
              ),
              away: GoalComparisonTeam(
                color: '000000',
                playerIds: g.$1 ? ['other'] : ['player'],
              ),
              homeScore: g.$1 ? g.$2 : g.$3,
              awayScore: g.$1 ? g.$3 : g.$2,
            ),
          for (var i = 0; i < 10; i++)
            const GoalComparisonMatch(
              home: GoalComparisonTeam(color: 'ffffff', playerIds: ['other']),
              away: GoalComparisonTeam(color: '000000', playerIds: ['third']),
              homeScore: 2,
              awayScore: 1,
            ),
        ],
      ),
      playerMatchesProvider.overrideWith(
        (ref, id) async => [
          for (final (i, g) in games.indexed)
            Match(
              matchId: '${i + 1}',
              squadId: 'demo',
              homeScore: g.$1 ? g.$2 : g.$3,
              awayScore: g.$1 ? g.$3 : g.$2,
              createdAt: DateTime(2026, 9, 3 + 6 * i),
              homeTeam: Team(
                teamId: 'h$i',
                matchId: '${i + 1}',
                side: Side.home,
                name: 'Gospodarze',
                color: 'ffffff',
              ),
              awayTeam: Team(
                teamId: 'a$i',
                matchId: '${i + 1}',
                side: Side.away,
                name: 'Goście',
                color: '000000',
              ),
            ),
        ],
      ),
      squadMatchLevelsProvider.overrideWith((ref, id) async => {}),
      playerTournamentsProvider.overrideWith(
        (ref, key) async => games.isEmpty
            ? []
            : [
                Tournament(
                  tournamentId: 'cup',
                  squadId: 'demo',
                  name: 'Puchar demonstracyjny',
                  status: TournamentStatus.completed,
                  createdAt: DateTime(2026, 9),
                  updatedAt: DateTime(2026, 10),
                ),
              ],
      ),
      playerStatsProvider.overrideWith(
        (ref, id) async => PlayerStatsViewState(
          stats: PlayerStats(
            baseRanking: 69,
            currentRanking: games.isEmpty ? 69 : games.last.$4,
            totalMatches: games.length,
            totalWins: games.where((g) => g.$2 > g.$3).length,
            totalDraws: games.where((g) => g.$2 == g.$3).length,
            totalLosses: games.where((g) => g.$2 < g.$3).length,
            winStreak: games.isEmpty ? 0 : 6,
            lossStreak: 0,
            biggestWinStreak: games.isEmpty ? 0 : 6,
            biggestLossStreak: games.isEmpty ? 0 : 1,
            goalsScored: games.fold(0, (s, g) => s + g.$2),
            goalsConceded: games.fold(0, (s, g) => s + g.$3),
            avgGoalsPerMatch: games.isEmpty
                ? 0
                : games.fold(0, (s, g) => s + g.$2) / games.length,
            avgScore: games.isEmpty
                ? 0
                : games.fold(0, (s, g) => s + g.$3) / games.length,
          ),
          headToHead: games.isEmpty
              ? []
              : [
                  for (final (i, peer) in [
                    'Ola Lis',
                    'Jan Mazur',
                    'Ewa Król',
                    'Adam Nowak',
                    'Iga Wilk',
                  ].indexed)
                    PlayerHeadToHeadStat.fromMap({
                      'other_player_id': '$i',
                      'other_name': peer,
                      'together_matches': 8 - i,
                      'together_wins': 7 - i,
                      'together_draws': 0,
                      'together_losses': 1,
                      'together_goals_for': 25 - i,
                      'together_goals_against': 10 - i,
                      'vs_matches': i,
                      'vs_wins': i,
                      'vs_draws': 0,
                      'vs_losses': 0,
                      'vs_goals_for': i * 3,
                      'vs_goals_against': i,
                    }),
                ],
        ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Column(
        children: [
          Material(
            color: Colors.amber,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'SYNTHETIC DATA · issue 79',
                      style: TextStyle(color: Colors.black, fontSize: 12),
                    ),
                  ),
                  Semantics(
                    label: 'Zmień motyw',
                    button: true,
                    child: IconButton(
                      onPressed: () => setState(() => dark = !dark),
                      icon: const Icon(Icons.brightness_6, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: child!),
        ],
      ),
    ),
  );
}
