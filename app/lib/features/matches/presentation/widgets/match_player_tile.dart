import 'package:app/core/widgets/player_transfer_drag.dart';
import 'package:flutter/material.dart';
import 'package:app/core/widgets/player_list_row.dart';
import 'package:app/features/matches/application/dto/player_dto.dart';

class MatchPlayerTile extends StatelessWidget {
  const MatchPlayerTile({
    super.key,
    required this.player,
    this.trailing,
    this.compact = false,
    this.density,
    this.leading,
    this.onTap,
    this.dragData,
    this.snapshotRanking,
    this.onDragStarted,
    this.onDragEnd,
  });

  final PlayerDto player;
  final Widget? trailing;
  final bool compact;
  final PlayerRowDensity? density;
  final Widget? leading;
  final VoidCallback? onTap;
  final Object? dragData;

  /// If provided, this ranking is shown instead of player.ranking
  final double? snapshotRanking;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    // In match history, we should show the snapshot ranking if available.
    final displayRanking = snapshotRanking ?? player.ranking;
    final tile = PlayerListRow(
      name: player.name,
      ranking: displayRanking,
      compact: compact,
      density: density,
      leading:
          leading ??
          (dragData == null
              ? null
              : const Tooltip(
                  triggerMode: TooltipTriggerMode.manual,
                  message: 'Przytrzymaj i przeciągnij',
                  child: Icon(Icons.drag_indicator, size: 16),
                )),
      trailing: trailing,
      onTap: onTap,
    );

    final data = dragData;
    if (data == null) {
      return tile;
    }

    final feedback = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: compact
            ? (MediaQuery.sizeOf(context).width < 640
                  ? MediaQuery.sizeOf(context).width / 2 - 8
                  : 320)
            : 520,
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: tile,
      ),
    );

    return PlayerTransferDrag(
      data: data,
      feedback: feedback,
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      child: tile,
    );
  }
}

// Intentionally no ranking change indicator here. Match details should show
// only the snapshot ranking.
