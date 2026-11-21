import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/error/failure.dart';
import 'package:app/features/players/application/player_goal_comparison_provider.dart';
import '../widgets/squad_role_goal_section.dart';
import 'package:app/features/squads/domain/entities/squad_stats.dart';
import 'package:app/features/squads/presentation/state/squad_stats_provider.dart';
import 'package:app/features/squads/presentation/widgets/stat_tile.dart';

class SquadStatsPage extends ConsumerWidget {
  const SquadStatsPage({super.key, required this.squadId});

  final String squadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsState = ref.watch(squadStatsProvider(squadId));

    return Scaffold(
      appBar: AppBar(title: const Text('Statystyki')),
      body: statsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _StatsErrorView(
          message: _errorMessage(error),
          onRetry: () => ref.invalidate(squadStatsProvider(squadId)),
        ),
        data: (stats) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(squadGoalHistoryProvider(squadId));
            ref.invalidate(squadRoleGoalComparisonsProvider(squadId));
            await Future.wait([
              ref.refresh(squadStatsProvider(squadId).future),
              ref.read(squadRoleGoalComparisonsProvider(squadId).future),
            ]);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SquadRoleGoalSection(squadId: squadId),
              const Divider(),
              ..._buildTiles(stats),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTiles(SquadStats stats) {
    final avgScoreText =
        '${stats.avgHomeGoals.toStringAsFixed(2)} : '
        '${stats.avgAwayGoals.toStringAsFixed(2)}';

    return [
      StatTile(label: 'Najlepszy gracz', value: stats.topPlayer),
      StatTile(label: 'Wschodząca gwiazda', value: stats.topRisingStar),
      const Divider(),
      StatTile(label: 'Mecze', value: stats.matchesCount),
      StatTile(label: 'Wszystkie gole', value: stats.totalGoals),
      StatTile(label: 'Gole gospodarzy', value: stats.totalHomeGoals),
      StatTile(label: 'Gole gości', value: stats.totalAwayGoals),
      StatTile(label: 'Średnia goli na mecz', value: stats.avgGoalsPerMatch),
      StatTile(
        label: 'Średni wynik (gospodarze : goście)',
        value: avgScoreText,
      ),
      const Divider(),
      StatTile(label: 'Gracze', value: stats.playersCount),
      StatTile(label: 'Średni ranking gracza', value: stats.avgPlayerScore),
    ];
  }

  String _errorMessage(Object error) {
    if (error is Failure) {
      return error.message;
    }
    return 'Nie udało się wczytać statystyk składu.';
  }
}

class _StatsErrorView extends StatelessWidget {
  const _StatsErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Ponów')),
          ],
        ),
      ),
    );
  }
}
