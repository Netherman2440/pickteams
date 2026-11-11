import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/app_router.dart';

class MatchTile extends StatelessWidget {
  final Match match;
  final String squadId;

  const MatchTile({super.key, required this.match, required this.squadId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = match.createdAt.toLocal();
    final fullDate = DateFormat('dd.MM.yyyy HH:mm').format(date);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );
    final hasScore = match.homeScore != null && match.awayScore != null;
    final teamsNotSelected = !hasScore && _teamsAreEmpty(match);

    return Card(
      child: InkWell(
        onTap: () {
          context.pushNamed(
            AppRoute.matchDetails.name,
            pathParameters: {'squadId': squadId, 'matchId': match.matchId},
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Tooltip(
                    message: fullDate,
                    excludeFromSemantics: true,
                    child: Semantics(
                      label: fullDate,
                      excludeSemantics: true,
                      child: Text(
                        DateFormat('dd.MM').format(date),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(),
                        1: IntrinsicColumnWidth(),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        _teamRow(
                          name: _displayTeamName(
                            match.homeTeam?.name,
                            'gospodarze',
                          ),
                          color: _parseColor(match.homeTeam?.color),
                          style: titleStyle,
                          score: teamsNotSelected
                              ? null
                              : hasScore
                              ? '${match.homeScore}'
                              : '-',
                        ),
                        _teamRow(
                          name: _displayTeamName(
                            match.awayTeam?.name,
                            'goście',
                          ),
                          color: _parseColor(match.awayTeam?.color),
                          style: titleStyle,
                          score: teamsNotSelected
                              ? null
                              : hasScore
                              ? '${match.awayScore}'
                              : '-',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (teamsNotSelected) ...[
                const SizedBox(height: 8),
                Text(
                  'Nie wybrano jeszcze drużyn',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

TableRow _teamRow({
  required String name,
  required Color color,
  required TextStyle? style,
  required String? score,
}) => TableRow(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _TeamColorBox(color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(name.toUpperCase(), style: style)),
        ],
      ),
    ),
    if (score == null)
      const SizedBox.shrink()
    else
      Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Text(
          score,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
  ],
);

bool _teamsAreEmpty(Match match) {
  final homeHasPlayers =
      (match.homeTeam?.players.isNotEmpty ?? false) ||
      ((match.homeTeam?.playerCount ?? 0) > 0);
  final awayHasPlayers =
      (match.awayTeam?.players.isNotEmpty ?? false) ||
      ((match.awayTeam?.playerCount ?? 0) > 0);

  return !homeHasPlayers && !awayHasPlayers;
}

String _displayTeamName(String? name, String fallback) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed;
}

Color _parseColor(String? colorHex) {
  if (colorHex == null || colorHex.isEmpty) return Colors.grey;
  try {
    final normalized = colorHex.trim();
    final hex = normalized.startsWith('#')
        ? normalized.substring(1)
        : normalized;
    if (hex.length != 6) return Colors.grey;
    return Color(int.parse('0xFF$hex'));
  } catch (_) {
    return Colors.grey;
  }
}

class _TeamColorBox extends StatelessWidget {
  final Color color;

  const _TeamColorBox({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
