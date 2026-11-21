// Version 1: issue 69's three-match synthetic acceptance dataset. No backend.
import 'package:app/core/app_theme.dart';
import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import 'package:app/features/players/application/usecases/get_squad_players_usecase.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/entities/player_stats.dart';
import 'package:app/features/players/domain/repositories/goal_comparison_repository.dart';
import 'package:app/features/players/domain/repositories/player_repository.dart';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/presentation/pages/player_stats_page.dart';
import 'package:app/features/players/presentation/state/player_name_provider.dart';
import 'package:app/features/players/presentation/state/player_stats_provider.dart';
import 'package:app/features/squads/domain/entities/squad_stats.dart';
import 'package:app/features/squads/presentation/pages/squad_stats_page.dart';
import 'package:app/features/squads/presentation/state/squad_stats_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'goal_comparison_data.dart';

List<GoalComparisonMatch> roleGoalFixture({
  String? homeColor = red,
  String? awayColor = blue,
}) => [
  goalMatch(
    homeScore: 5,
    awayScore: 2,
    homeColor: homeColor,
    awayColor: awayColor,
  ),
  goalMatch(
    homePlayers: ['other'],
    awayPlayers: ['player'],
    homeScore: 4,
    awayScore: 6,
    homeColor: awayColor,
    awayColor: homeColor,
  ),
  goalMatch(
    homePlayers: ['other'],
    awayPlayers: ['third'],
    homeScore: 2,
    awayScore: 3,
    homeColor: null,
    awayColor: null,
  ),
];

class RoleHistory implements GoalComparisonRepository {
  int reads = 0;
  bool fail = false;
  List<GoalComparisonMatch> matches = roleGoalFixture();
  @override
  Future<List<GoalComparisonMatch>> getSquadHistory(String squadId) async {
    reads++;
    if (fail) throw StateError('synthetic history failure');
    return matches;
  }
}

class RoleRoster implements PlayerRepository {
  int reads = 0;
  bool fail = false;
  @override
  Future<List<Player>> getSquadPlayers({required String squadId}) async {
    reads++;
    if (fail) throw StateError('synthetic roster failure');
    return [
      for (final entry in {
        'player': 'Jan Testowy',
        'other': 'Ola Testowa',
        'new': 'Nowy bez występów',
      }.entries)
        Player(
          playerId: entry.key,
          squadId: squadId,
          name: entry.value,
          ranking: 50,
          baseRanking: 50,
          createdAt: DateTime(2026),
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'No other repository operations in synthetic fixture: ${invocation.memberName}',
  );
}

class RoleGoalFixtureApp extends StatelessWidget {
  RoleGoalFixtureApp({
    super.key,
    this.squad = false,
    RoleHistory? history,
    RoleRoster? roster,
  }) : history = history ?? RoleHistory(),
       roster = roster ?? RoleRoster();
  final bool squad;
  final RoleHistory history;
  final RoleRoster roster;

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      goalComparisonRepositoryProvider.overrideWithValue(history),
      getSquadPlayersUseCaseProvider.overrideWithValue(
        GetSquadPlayersUseCase(roster),
      ),
      playerNameProvider.overrideWith((ref, id) async => 'Jan Testowy'),
      playerStatsProvider.overrideWith(
        (ref, id) async => PlayerStatsViewState(
          stats: PlayerStats.fromMap({
            'total_matches': 2,
            'total_wins': 2,
            'base_ranking': 50,
            'current_ranking': 50,
            'goals_scored': 11,
            'goals_conceded': 6,
            'avg_goals_per_match': 5.5,
            'avg_score': 3,
          }),
          headToHead: [],
        ),
      ),
      squadStatsProvider.overrideWith(
        (ref, id) async => SquadStats.fromMap({
          'matches_count': 3,
          'total_goals': 22,
          'total_home_goals': 11,
          'total_away_goals': 11,
          'players_count': 3,
        }),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) => Column(
        children: [
          const Material(
            color: Colors.amber,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'SYNTHETIC DATA · issue 69 · v1\nJan: home 5:2 · away 4:6 · absent 2:3',
                  style: TextStyle(color: Colors.black, fontSize: 12),
                ),
              ),
            ),
          ),
          Expanded(child: child!),
        ],
      ),
      home: squad
          ? const SquadStatsPage(squadId: 'synthetic')
          : const PlayerStatsPage(squadId: 'synthetic', playerId: 'player'),
    ),
  );
}
