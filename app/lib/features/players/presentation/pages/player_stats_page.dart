import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/error/failure.dart';
import '../../application/player_goal_comparison_provider.dart';
import '../widgets/player_role_goal_section.dart';
import 'package:app/features/players/domain/entities/player_stats.dart';
import 'package:app/features/players/presentation/state/player_name_provider.dart';
import 'package:app/features/players/presentation/state/player_stats_provider.dart';
import 'package:app/features/players/presentation/widgets/player_head_to_head_table.dart';
import 'package:app/features/squads/presentation/widgets/stat_tile.dart';

class PlayerStatsPage extends ConsumerStatefulWidget {
  const PlayerStatsPage({
    super.key,
    required this.squadId,
    required this.playerId,
  });

  final String squadId;
  final String playerId;

  @override
  ConsumerState<PlayerStatsPage> createState() => _PlayerStatsPageState();
}

class _PlayerStatsPageState extends ConsumerState<PlayerStatsPage> {
  HeadToHeadColumn _sortColumn = HeadToHeadColumn.togetherMatches;
  bool _sortAscending = false;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(playerStatsProvider(widget.playerId));
    final playerNameAsync = ref.watch(playerNameProvider(widget.playerId));
    final title = playerNameAsync.maybeWhen(
      data: (name) => '$name > Statystyki',
      orElse: () => 'Statystyki',
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _StatsErrorView(message: _errorMessage(error)),
        data: (state) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(squadGoalHistoryProvider(widget.squadId));
            await Future.wait([
              ref.refresh(playerStatsProvider(widget.playerId).future),
              ref.read(
                playerRoleGoalComparisonProvider((
                  squadId: widget.squadId,
                  playerId: widget.playerId,
                )).future,
              ),
            ]);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              PlayerRoleGoalSection(
                squadId: widget.squadId,
                playerId: widget.playerId,
              ),
              const Divider(),
              ..._buildStatTiles(state.stats),
              const SizedBox(height: 24),
              Text(
                'Bezpośrednie pojedynki',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: PlayerHeadToHeadTable(
                  stats: state.headToHead,
                  sortColumn: _sortColumn,
                  sortAscending: _sortAscending,
                  onSort: (column, ascending) {
                    setState(() {
                      _sortColumn = column;
                      _sortAscending = ascending;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStatTiles(PlayerStats stats) {
    final avgScoreText =
        '${stats.avgGoalsPerMatch.toStringAsFixed(2)} : '
        '${stats.avgScore.toStringAsFixed(2)}';

    return [
      StatTile(label: 'Ranking bazowy', value: stats.baseRanking),
      StatTile(label: 'Aktualny ranking', value: stats.currentRanking),
      const Divider(),
      StatTile(label: 'Liczba meczów', value: stats.totalMatches),
      StatTile(label: 'Liczba zwycięstw', value: stats.totalWins),
      StatTile(label: 'Liczba remisów', value: stats.totalDraws),
      StatTile(label: 'Liczba porażek', value: stats.totalLosses),
      const Divider(),
      StatTile(label: 'Aktualna seria zwycięstw', value: stats.winStreak),
      StatTile(label: 'Aktualna seria porażek', value: stats.lossStreak),
      StatTile(
        label: 'Najdłuższa seria zwycięstw',
        value: stats.biggestWinStreak,
      ),
      StatTile(
        label: 'Najdłuższa seria porażek',
        value: stats.biggestLossStreak,
      ),
      const Divider(),
      StatTile(label: 'Strzelone gole', value: stats.goalsScored),
      StatTile(label: 'Stracone gole', value: stats.goalsConceded),
      StatTile(
        label: 'Średnio strzelonych goli na mecz',
        value: stats.avgGoalsPerMatch,
      ),
      StatTile(
        label: 'Średni wynik (strzelone : stracone)',
        value: avgScoreText,
      ),
    ];
  }

  String _errorMessage(Object error) {
    if (error is Failure) {
      return error.message;
    }
    return 'Nie udało się wczytać statystyk gracza.';
  }
}

class _StatsErrorView extends StatelessWidget {
  const _StatsErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
