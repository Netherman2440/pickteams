import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../domain/entities/ranking_history_entry.dart';
import 'ranking_history_viewport.dart';

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
  late List<RankingHistoryEntry> _history;
  late RankingHistoryViewport _view;
  int? _selected;
  double _gestureSpan = 0;
  double _gestureAnchor = 0;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _history = widget.history.where((e) => e.change != null).toList()
      ..sort((a, b) {
        final date = a.createdAt.compareTo(b.createdAt);
        return date != 0
            ? date
            : a.rankingHistoryId.compareTo(b.rankingHistoryId);
      });
    _view = RankingHistoryViewport(_history.length);
    _selected = null;
  }

  @override
  void didUpdateWidget(covariant RankingHistoryGraphWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history) _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _change(VoidCallback action) => setState(() {
    action();
    _selected = null;
  });

  void _select(int index) => setState(() {
    _selected = index.clamp(0, _history.length - 1);
    if (_selected! < _view.start) {
      _view.setWindow(_selected!.toDouble(), _view.span);
    }
    if (_selected! > _view.end) {
      _view.setWindow(_selected! - _view.span, _view.span);
    }
  });

  @override
  Widget build(BuildContext context) {
    if (_history.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Brak zmian rankingu')),
      );
    }
    final selected = _selected ?? _view.end.floor();
    String pointLabel(int index) {
      final entry = _history[index];
      return '${DateFormat('dd.MM.yyyy').format(entry.createdAt.toLocal())} · ${entry.currentRanking.toStringAsFixed(2)} pkt';
    }

    final readout = pointLabel(selected);
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _change(() => _view.pan(-1)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _change(() => _view.pan(1)),
        const SingleActivator(LogicalKeyboardKey.home): () =>
            _change(() => _view.setWindow(0, _view.span)),
        const SingleActivator(LogicalKeyboardKey.end): () =>
            _change(_view.latest),
        const SingleActivator(LogicalKeyboardKey.equal): () =>
            _change(() => _view.zoom(1 / 1.45, .5)),
        const SingleActivator(LogicalKeyboardKey.equal, shift: true): () =>
            _change(() => _view.zoom(1 / 1.45, .5)),
        const SingleActivator(LogicalKeyboardKey.minus): () =>
            _change(() => _view.zoom(1.45, .5)),
      },
      child: Focus(
        focusNode: _focus,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mecze ${_view.start.ceil() + 1}–${_view.end.floor() + 1} z ${_history.length}',
            ),
            Semantics(liveRegion: true, child: Text(readout)),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = math.max(1.0, constraints.maxWidth - 48);
                double fraction(double x) => (x / width).clamp(0, 1);
                return Semantics(
                  label: 'Historia rankingu',
                  value: readout,
                  increasedValue: selected < _history.length - 1
                      ? pointLabel(selected + 1)
                      : null,
                  decreasedValue: selected > 0
                      ? pointLabel(selected - 1)
                      : null,
                  hint:
                      'Strzałki przesuwają historię. Plus i minus zmieniają skalę. Home: początek. End: najnowsze.',
                  onIncrease: selected < _history.length - 1
                      ? () => _select(selected + 1)
                      : null,
                  onDecrease: selected > 0 ? () => _select(selected - 1) : null,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    onHover: (event) => _select(
                      (_view.start +
                              fraction(event.localPosition.dx) * _view.span)
                          .round(),
                    ),
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is! PointerScrollEvent) return;
                        GestureBinding.instance.pointerSignalResolver.register(
                          event,
                          (_) {
                            _focus.requestFocus();
                            _change(() {
                              if (HardwareKeyboard.instance.isShiftPressed ||
                                  event.scrollDelta.dx.abs() >
                                      event.scrollDelta.dy.abs()) {
                                final delta = event.scrollDelta.dx != 0
                                    ? event.scrollDelta.dx
                                    : event.scrollDelta.dy;
                                _view.pan(delta * _view.span / width);
                              } else {
                                _view.zoom(
                                  math.exp(
                                    (event.scrollDelta.dy * .003).clamp(-1, 1),
                                  ),
                                  fraction(event.localPosition.dx),
                                );
                              }
                            });
                          },
                        );
                      },
                      child: GestureDetector(
                        key: const ValueKey('ranking-plot'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          _focus.requestFocus();
                          _select(
                            (_view.start +
                                    fraction(details.localPosition.dx) *
                                        _view.span)
                                .round(),
                          );
                        },
                        onScaleStart: (details) {
                          _focus.requestFocus();
                          _gestureSpan = _view.span;
                          _gestureAnchor =
                              _view.start +
                              fraction(details.localFocalPoint.dx) * _view.span;
                        },
                        onScaleUpdate: (details) => _change(() {
                          final span = (_gestureSpan / details.scale).clamp(
                            _view.minSpan,
                            _view.last,
                          );
                          _view.setWindow(
                            _gestureAnchor -
                                fraction(details.localFocalPoint.dx) * span,
                            span,
                          );
                        }),
                        child: ExcludeSemantics(
                          child: CustomPaint(
                            size: const Size(double.infinity, 200),
                            painter: _RankingPainter(
                              history: _history,
                              start: _view.start,
                              span: _view.span,
                              selected: selected,
                              color: theme.colorScheme.primary,
                              labelStyle: theme.textTheme.labelSmall!.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textScaler: MediaQuery.textScalerOf(context),
                              direction: Directionality.of(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Oddal wykres',
                  onPressed: _view.span < _view.last
                      ? () => _change(() => _view.zoom(1.45, .5))
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: 'Przybliż wykres',
                  onPressed: _view.span > _view.minSpan
                      ? () => _change(() => _view.zoom(1 / 1.45, .5))
                      : null,
                  icon: const Icon(Icons.add),
                ),
                TextButton(
                  onPressed: _view.end < _view.last
                      ? () => _change(_view.latest)
                      : null,
                  child: const Text('Do najnowszego'),
                ),
                TextButton(
                  onPressed: _view.span < _view.last
                      ? () => _change(_view.reset)
                      : null,
                  child: const Text('Cały zakres'),
                ),
                IconButton(
                  tooltip: 'Poprzedni punkt',
                  onPressed: selected > 0 ? () => _select(selected - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Następny punkt',
                  onPressed: selected < _history.length - 1
                      ? () => _select(selected + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Text(
              'Przeciągnij, aby przesunąć historię. Rozsuń palce lub użyj kółka, aby zmienić skalę. Dotknij punktu, aby odczytać ranking.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingPainter extends CustomPainter {
  const _RankingPainter({
    required this.history,
    required this.start,
    required this.span,
    required this.selected,
    required this.color,
    required this.labelStyle,
    required this.textScaler,
    required this.direction,
  });
  final List<RankingHistoryEntry> history;
  final double start, span;
  final int selected;
  final Color color;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final width = math.max(1.0, size.width - 48);
    final bottom = size.height - 38;
    final values = history.map((e) => e.currentRanking);
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final padding = math.max(1.0, (high - low) * .15);
    final min = low - padding, max = high + padding;
    double x(int i) => span == 0 ? width / 2 : (i - start) * width / span;
    double y(double value) => 10 + (max - value) / (max - min) * (bottom - 10);
    void label(String text, double dx, double dy) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textScaler: textScaler,
        textDirection: direction,
      )..layout();
      painter.paint(
        canvas,
        Offset(dx.clamp(0, math.max(0, size.width - painter.width)), dy),
      );
    }

    for (var i = 0; i < 3; i++) {
      final value = min + (max - min) * i / 2;
      canvas.drawLine(
        Offset(0, y(value)),
        Offset(width, y(value)),
        Paint()..color = color.withValues(alpha: .15),
      );
      label(value.toStringAsFixed(0), width + 5, y(value) - 7);
    }
    final first = start.floor().clamp(0, history.length - 1);
    final last = (start + span).ceil().clamp(0, history.length - 1);
    final path = Path()..moveTo(x(first), y(history[first].currentRanking));
    for (var i = first + 1; i <= last; i++) {
      path.lineTo(x(i), y(history[i].currentRanking));
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, width, bottom + 4));
    final area = Path.from(path)
      ..lineTo(x(last), bottom)
      ..lineTo(x(first), bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: .12));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (var i = first; i <= last; i++) {
      if (span < 20 || i == selected) {
        canvas.drawCircle(
          Offset(x(i), y(history[i].currentRanking)),
          i == selected ? 5 : 3,
          Paint()..color = color,
        );
      }
    }
    canvas.restore();
    final lo = start.ceil(), hi = (start + span).floor();
    label(
      DateFormat('dd.MM').format(history[lo].createdAt.toLocal()),
      0,
      bottom + 8,
    );
    if (lo != hi) {
      label(
        DateFormat('dd.MM').format(history[hi].createdAt.toLocal()),
        width - 36,
        bottom + 8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RankingPainter oldDelegate) => true;
}
