import 'package:flutter/material.dart';
import '../widgets/player_context_header.dart';
import '../widgets/player_navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:app/core/app_router.dart';
import 'package:app/features/players/presentation/state/player_tournaments_provider.dart';
import 'package:app/features/tournaments/domain/entities/tournament.dart';
import 'package:app/features/tournaments/domain/entities/tournament_status.dart';

class PlayerTournamentsPage extends ConsumerWidget {
  const PlayerTournamentsPage({
    super.key,
    required this.squadId,
    required this.playerId,
  });

  final String squadId;
  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = (squadId: squadId, playerId: playerId);
    final tournamentsAsync = ref.watch(playerTournamentsProvider(params));

    return Scaffold(
      appBar: AppBar(title: const Text('Turnieje')),
      body: PlayerContent(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PlayerContextHeader(
                squadId: squadId,
                playerId: playerId,
                selected: PlayerSection.tournaments,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(playerTournamentsProvider(params).future),
                child: tournamentsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: SelectableText.rich(
                      TextSpan(
                        text: 'Błąd: $error',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                  data: (tournaments) {
                    if (tournaments.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('Nie znaleziono turniejów.')),
                        ],
                      );
                    }

                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: tournaments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final tournament = tournaments[index];
                        return _TournamentTile(
                          squadId: squadId,
                          tournament: tournament,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TournamentTile extends StatelessWidget {
  const _TournamentTile({required this.squadId, required this.tournament});

  final String squadId;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat(
      'dd.MM.yyyy HH:mm',
    ).format(tournament.createdAt.toLocal());

    return Card(
      child: ListTile(
        onTap: () {
          context.pushNamed(
            AppRoute.tournamentDetails.name,
            pathParameters: {
              'squadId': squadId,
              'tournamentId': tournament.tournamentId,
            },
          );
        },
        leading: const Icon(Icons.emoji_events_outlined),
        title: Text(_displayTournamentName(tournament)),
        subtitle: Text('Utworzono: $dateText'),
        trailing: _StatusLabel(status: tournament.status),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final TournamentStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      TournamentStatus.drafting => (
        'Nie wybrano drużyn',
        scheme.onSurfaceVariant,
      ),
      TournamentStatus.active => ('Aktywny', scheme.primary),
      TournamentStatus.completed => ('Zakończony', Colors.grey),
    };

    return Text(
      label,
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

String _displayTournamentName(Tournament tournament) {
  final value = tournament.name?.trim();
  if (value == null || value.isEmpty) {
    return 'Turniej ${tournament.createdAt.day}.${tournament.createdAt.month}';
  }
  return value;
}
