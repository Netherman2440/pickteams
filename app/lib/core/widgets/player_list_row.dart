import 'package:flutter/material.dart';

/// A growing row: mobile rankings sit below names; desktop keeps them inline.
class PlayerListRow extends StatelessWidget {
  const PlayerListRow({
    super.key,
    required this.name,
    required this.ranking,
    required this.compact,
    this.trailing,
    this.onTap,
  });

  final String name;
  final double ranking;
  final bool compact;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameText = Text(
      name,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 18 / 14,
      ),
    );
    final rankingText = Text(
      ranking.toStringAsFixed(2),
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: compact ? 11 : 12,
        height: 13 / 11,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 42 : 48),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: .35),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [nameText, rankingText],
                      )
                    : Row(
                        children: [
                          Expanded(child: nameText),
                          const SizedBox(width: 12),
                          rankingText,
                        ],
                      ),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
