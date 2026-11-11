import 'package:flutter/material.dart';

/// Density sets a minimum, not a fixed height: long names and large text grow.
enum PlayerRowDensity { compact, comfortable }

/// Shared inline name/rating geometry for rosters and interactive player lists.
class PlayerListRow extends StatelessWidget {
  const PlayerListRow({
    super.key,
    required this.name,
    required this.ranking,
    this.compact = false,
    this.density,
    this.leading,
    this.trailing,
    this.supporting,
    this.onTap,
  });

  final String name;
  final double ranking;

  /// Compatibility for existing roster callers. Prefer [density] in new code.
  final bool compact;
  final PlayerRowDensity? density;
  final Widget? leading;
  final Widget? trailing;

  /// Optional metadata; the name and rating always keep their inline layout.
  final Widget? supporting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact =
        (density ??
            (compact
                ? PlayerRowDensity.compact
                : PlayerRowDensity.comfortable)) ==
        PlayerRowDensity.compact;
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
        fontSize: 12,
        height: 16 / 12,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: isCompact ? 32 : 48),
          padding: EdgeInsets.symmetric(
            horizontal: 4,
            vertical: isCompact ? 3 : 8,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: .35),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  Expanded(child: nameText),
                  const SizedBox(width: 8),
                  rankingText,
                  if (trailing != null) ...[
                    const SizedBox(width: 4),
                    trailing!,
                  ],
                ],
              ),
              if (supporting != null) ...[
                const SizedBox(height: 4),
                supporting!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
