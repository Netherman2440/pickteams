import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/player_position.dart';
import '../controllers/player_details_controller.dart';
import '../state/player_name_provider.dart';
import 'player_navigation.dart';

/// Full destinations keep the same player context, including direct links.
class PlayerContextHeader extends ConsumerWidget {
  const PlayerContextHeader({
    super.key,
    required this.squadId,
    required this.playerId,
    required this.selected,
  });
  final String squadId;
  final String playerId;
  final PlayerSection selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref
        .watch(playerDetailsProvider(playerId))
        .asData
        ?.value
        .player;
    final name =
        player?.name ??
        ref.watch(playerNameProvider(playerId)).asData?.value ??
        'Zawodnik';
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                child: Text(
                  name.trim().isEmpty
                      ? '?'
                      : name
                            .trim()
                            .split(RegExp(r'\s+'))
                            .take(2)
                            .map((p) => p[0])
                            .join()
                            .toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleLarge),
                    if (player != null)
                      Text(
                        playerPositionPolishLabel(player.position) ??
                            'Brak pozycji',
                      ),
                  ],
                ),
              ),
              if (player != null) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Ranking'),
                    Text(
                      player.ranking.toStringAsFixed(2),
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        PlayerNavigation(
          squadId: squadId,
          playerId: playerId,
          selected: selected,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
