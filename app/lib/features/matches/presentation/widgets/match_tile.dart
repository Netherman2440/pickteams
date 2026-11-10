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
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    final homeTeamName = _displayTeamName(
      match.homeTeam?.name,
      'gospodarze',
    ).toUpperCase();
    final awayTeamName = _displayTeamName(
      match.awayTeam?.name,
      'goście',
    ).toUpperCase();
    final homeTeamColor = _parseColor(match.homeTeam?.color);
    final awayTeamColor = _parseColor(match.awayTeam?.color);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );
    final hasScore = match.homeScore != null && match.awayScore != null;
    final teamsNotSelected = !hasScore && _teamsAreEmpty(match);
    final homeScore = hasScore ? match.homeScore.toString() : '-';
    final awayScore = hasScore ? match.awayScore.toString() : '-';

    return Card(
      child: InkWell(
        onTap: () {
          context.pushNamed(
            AppRoute.matchDetails.name,
            pathParameters: {'squadId': squadId, 'matchId': match.matchId},
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <
                  600 * MediaQuery.textScalerOf(context).scale(14) / 14) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TeamRow(
                      name: homeTeamName,
                      color: homeTeamColor,
                      style: titleStyle,
                      score: teamsNotSelected ? null : homeScore,
                    ),
                    const SizedBox(height: 8),
                    _TeamRow(
                      name: awayTeamName,
                      color: awayTeamColor,
                      style: titleStyle,
                      score: teamsNotSelected ? null : awayScore,
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
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(match.createdAt.toLocal()),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: _TeamColorBox(color: homeTeamColor),
                              ),
                              TextSpan(
                                text: ' $homeTeamName',
                                style: titleStyle,
                              ),
                              TextSpan(text: '  -  ', style: titleStyle),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: _TeamColorBox(color: awayTeamColor),
                              ),
                              TextSpan(
                                text: ' $awayTeamName',
                                style: titleStyle,
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(match.createdAt.toLocal()),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (teamsNotSelected)
                    Text(
                      'Nie wybrano jeszcze drużyn',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Row(
                      children: [
                        _ScoreBox(score: homeScore),
                        const SizedBox(width: 8),
                        const Text(':'),
                        const SizedBox(width: 8),
                        _ScoreBox(score: awayScore),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.name,
    required this.color,
    required this.style,
    required this.score,
  });

  final String name;
  final Color color;
  final TextStyle? style;
  final String? score;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _TeamColorBox(color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(name, style: style)),
      if (score != null) ...[
        const SizedBox(width: 12),
        _ScoreBox(score: score!),
      ],
    ],
  );
}

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

class _ScoreBox extends StatelessWidget {
  final String score;

  const _ScoreBox({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.textScalerOf(
        context,
      ).scale(40).clamp(40, double.infinity),
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        score,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
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
