import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/ranking_history_entry.dart';

class RankingHistoryGraphWidget extends StatefulWidget {
  final List<RankingHistoryEntry> history;
  final double baseRanking;

  const RankingHistoryGraphWidget({
    super.key,
    required this.history,
    required this.baseRanking,
  });

  @override
  State<RankingHistoryGraphWidget> createState() => _RankingHistoryGraphState();
}

class _RankingHistoryGraphState extends State<RankingHistoryGraphWidget> {
  int? _end;
  String? _selectedId;

  @override
  void didUpdateWidget(covariant RankingHistoryGraphWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history) {
      _end = null;
      _selectedId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.history.where((e) => e.change != null).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (history.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Brak zmian rankingu')),
      );
    }
    final end = (_end ?? history.length).clamp(1, history.length);
    final start = math.max(0, end - 6);
    final visible = history.sublist(start, end);
    final selected = history.firstWhere(
      (e) => e.rankingHistoryId == _selectedId,
      orElse: () => visible.last,
    );
    void move(int direction) => setState(() {
      _end = (end + direction * 6).clamp(
        math.min(6, history.length),
        history.length,
      );
      _selectedId = null;
    });
    final spots = [
      for (var i = 0; i < visible.length; i++)
        FlSpot(i.toDouble(), visible[i].currentRanking),
    ];
    final values = spots.map((e) => e.y);
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final padding = math.max(1.0, (high - low) * .15);
    final date = DateFormat('dd.MM.yyyy');
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => move(1),
      },
      child: Focus(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Mecze ${start + 1}–$end z ${history.length}'),
                ),
                IconButton(
                  tooltip: 'Wcześniejsze mecze',
                  onPressed: start > 0 ? () => move(-1) : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: 'Nowsze mecze',
                  onPressed: end < history.length ? () => move(1) : null,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity.abs() > 50) move(velocity > 0 ? -1 : 1);
              },
              child: SizedBox(
                height: 170,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: math.max(1, visible.length - 1).toDouble(),
                    minY: low - padding,
                    maxY: high + padding,
                    gridData: const FlGridData(
                      show: true,
                      drawVerticalLine: false,
                    ),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: false,
                      touchCallback: (event, response) {
                        if (event is FlTapUpEvent &&
                            response?.lineBarSpots?.isNotEmpty == true) {
                          final index = response!.lineBarSpots!.first.spotIndex;
                          setState(
                            () => _selectedId = visible[index].rankingHistoryId,
                          );
                        }
                      },
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        color: theme.colorScheme.primary,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: theme.colorScheme.primary.withValues(
                            alpha: .12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  duration: Duration.zero,
                ),
              ),
            ),
            Row(
              children: [
                for (final entry in visible)
                  Expanded(
                    child: Semantics(
                      selected:
                          selected.rankingHistoryId == entry.rankingHistoryId,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: () => setState(
                          () => _selectedId = entry.rankingHistoryId,
                        ),
                        child: Text(
                          DateFormat('dd.MM').format(entry.createdAt.toLocal()),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                '${selected.matchId == null ? 'Zmiana rankingu' : 'Mecz ${selected.matchId}'} · ${date.format(selected.createdAt.toLocal())} · ${selected.currentRanking.toStringAsFixed(2)} pkt',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Przesuń wykres lub użyj strzałek. Dotknij punktu lub daty, aby odczytać ranking.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
