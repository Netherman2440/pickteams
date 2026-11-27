import 'dart:math' as math;

/// Index-based spacing keeps irregular match dates readable without inventing data.
class RankingHistoryViewport {
  RankingHistoryViewport(int count) : last = math.max(0, count - 1).toDouble() {
    span = math.min(11, last);
    start = last - span;
  }

  final double last;
  late double start;
  late double span;
  double get minSpan => math.min(3, last);
  double get end => start + span;

  void setWindow(double offset, double extent) {
    span = extent.clamp(minSpan, last);
    start = offset.clamp(0, last - span);
  }

  void pan(double delta) => setWindow(start + delta, span);

  void zoom(double factor, double fraction) {
    final anchor = start + fraction * span;
    final next = (span * factor).clamp(minSpan, last);
    setWindow(anchor - fraction * next, next);
  }

  void latest() => setWindow(last - span, span);
  void reset() => setWindow(0, last);
}
