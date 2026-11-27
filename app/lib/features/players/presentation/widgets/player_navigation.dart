import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/app_router.dart';
import '../../application/player_goal_comparison_provider.dart';

enum PlayerSection { profile, matches, tournaments, stats }

/// Contextual destinations retain the player id and the caller's back stack.
class PlayerNavigation extends ConsumerWidget {
  const PlayerNavigation({
    super.key,
    required this.squadId,
    required this.playerId,
    required this.selected,
  });

  final String squadId;
  final String playerId;
  final PlayerSection selected;

  static const labels = ['Profil', 'Mecze', 'Turnieje', 'Statystyki'];
  static const routes = [
    AppRoute.playerDetails,
    AppRoute.playerMatches,
    AppRoute.playerTournaments,
    AppRoute.playerStats,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Row(
          children: [
            for (final section in PlayerSection.values)
              Expanded(
                child: Semantics(
                  selected: section == selected,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 3,
                          color: section == selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        minimumSize: const Size(0, 48),
                        foregroundColor: section == selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        shape: const RoundedRectangleBorder(),
                      ),
                      onPressed: () async {
                        if (section == selected) return;
                        await context.pushNamed(
                          routes[section.index].name,
                          pathParameters: {
                            'squadId': squadId,
                            'playerId': playerId,
                          },
                        );
                        if (context.mounted) {
                          ref.invalidate(squadGoalHistoryProvider(squadId));
                        }
                      },
                      child: Text(labels[section.index], maxLines: 1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A bounded content column avoids stretching cards across large monitors.
class PlayerContent extends StatelessWidget {
  const PlayerContent({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
