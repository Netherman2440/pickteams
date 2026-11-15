import 'package:flutter/material.dart';

/// The parent row stretches both targets to the taller roster, including empty
/// teams. The minimum also leaves a usable target when both teams are short.
class TeamTransferTarget extends StatelessWidget {
  const TeamTransferTarget({
    super.key,
    required this.playerIds,
    required this.onAccept,
    required this.child,
  });

  final Iterable<String> playerIds;
  final ValueChanged<String> onAccept;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<Object>(
    onWillAcceptWithDetails: (details) =>
        details.data is String && !playerIds.contains(details.data),
    onAcceptWithDetails: (details) => onAccept(details.data as String),
    builder: (context, candidates, rejected) {
      final scheme = Theme.of(context).colorScheme;
      final active = candidates.isNotEmpty;
      return Container(
        constraints: const BoxConstraints(minHeight: 144),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: .12)
              : Colors.transparent,
          border: Border.all(
            color: scheme.onSurfaceVariant,
            width: active ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );
    },
  );
}
