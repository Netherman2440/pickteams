import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/app_router.dart';
import 'package:app/core/widgets/player_list_row.dart';

import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/entities/player_position.dart';

class PlayersListWidget extends StatelessWidget {
  const PlayersListWidget({
    super.key,
    required this.players,
    required this.squadId,
  });

  final List<Player> players;
  final String squadId;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        final difference = player.ranking - player.baseRanking;
        final positionText = playerPositionPolishLabel(player.position);
        final differenceWidget = difference == 0
            ? null
            : _RankingDifference(difference: difference);

        return PlayerListRow(
          name: player.name,
          ranking: player.ranking,
          density: PlayerRowDensity.comfortable,
          onTap: () {
            context.pushNamed(
              AppRoute.playerDetails.name,
              pathParameters: {'squadId': squadId, 'playerId': player.playerId},
            );
          },
          // Without a position the ranking and its delta stack into one
          // right-hand block and the name centers vertically against it.
          rankingSupport: positionText == null ? differenceWidget : null,
          supporting: positionText != null
              ? Row(
                  children: [
                    Expanded(child: Text(positionText)),
                    if (differenceWidget != null) ...[
                      const SizedBox(width: 12),
                      differenceWidget,
                    ],
                  ],
                )
              : null,
        );
      },
    );
  }
}

class _RankingDifference extends StatelessWidget {
  const _RankingDifference({required this.difference});

  final double difference;

  @override
  Widget build(BuildContext context) {
    final isPositiveOrFlat = difference >= 0;
    final color = isPositiveOrFlat ? Colors.green : Colors.red;
    final formattedDifference =
        '${difference >= 0 ? '+' : ''}'
        '${difference.toStringAsFixed(2)}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isPositiveOrFlat ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          formattedDifference,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
