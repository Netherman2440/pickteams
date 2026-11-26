import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:app/core/app_router.dart';
import '../../application/player_goal_comparison_provider.dart';
import '../state/player_matches_provider.dart';
import 'player_goal_comparison_section.dart';

class PlayerProfilePreviews extends ConsumerWidget {
  const PlayerProfilePreviews({
    super.key,
    required this.squadId,
    required this.playerId,
  });
  final String squadId;
  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(playerMatchesProvider(playerId));
    Future<void> open(AppRoute route) async {
      await context.pushNamed(
        route.name,
        pathParameters: {'squadId': squadId, 'playerId': playerId},
      );
      if (context.mounted) {
        ref.invalidate(squadGoalHistoryProvider(squadId));
        ref.invalidate(playerMatchesProvider(playerId));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayerPreviewCard(
          label: 'Otwórz pełne statystyki zawodnika',
          onTap: () => open(AppRoute.playerStats),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The entire card is one keyboard target, including the two tiles.
              IgnorePointer(
                child: PlayerGoalComparisonSection(
                  squadId: squadId,
                  playerId: playerId,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Porównaj gospodarzy i gości →',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PlayerPreviewCard(
          label: 'Otwórz wszystkie mecze zawodnika',
          onTap: () => open(AppRoute.playerMatches),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    'Ostatnie mecze',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Wszystkie${matches.asData == null ? '' : ' (${matches.asData!.value.length})'} →',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              matches.when(
                loading: () => const Text('Wczytywanie meczów…'),
                error: (_, _) => const Text(
                  'Nie udało się pobrać meczów. Otwórz historię, aby spróbować ponownie.',
                ),
                data: (all) {
                  final recent = [...all]
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  if (recent.isEmpty)
                    return const Text('Nie znaleziono meczów.');
                  return Column(
                    children: [
                      for (final match in recent.take(3)) ...[
                        const Divider(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${DateFormat('dd.MM.yyyy').format(match.createdAt.toLocal())}\n${match.homeTeam?.name ?? 'Gospodarze'} – ${match.awayTeam?.name ?? 'Goście'}',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${match.homeScore ?? '—'} : ${match.awayScore ?? '—'}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PlayerPreviewCard extends StatelessWidget {
  const PlayerPreviewCard({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
  });
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}
