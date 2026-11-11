import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One pinned identity above both columns; the roster has a single scroll axis.
class LineupHeader extends StatelessWidget {
  const LineupHeader({
    super.key,
    required this.homeName,
    required this.awayName,
    required this.homeColor,
    required this.awayColor,
  });

  final String homeName;
  final String awayName;
  final Color homeColor;
  final Color awayColor;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final style = Theme.of(context).textTheme.titleSmall!;
      final scaler = MediaQuery.textScalerOf(context);
      // Reserve the largest badge width when measuring so neither transition
      // nor large text can clip a team name.
      double nameHeight(String name) =>
          (TextPainter(
                text: TextSpan(text: name, style: style),
                textDirection: Directionality.of(context),
                textScaler: scaler,
              )..layout(
                maxWidth: math.max(
                  1,
                  (constraints.crossAxisExtent - 24) / 2 - 56,
                ),
              ))
              .height;
      final minimum = math.max(
        36.0,
        math.max(nameHeight(homeName), nameHeight(awayName)) + 8,
      );
      return SliverPersistentHeader(
        pinned: true,
        delegate: _LineupHeaderDelegate(
          homeName: homeName,
          awayName: awayName,
          homeColor: homeColor,
          awayColor: awayColor,
          minimum: minimum,
          style: style,
        ),
      );
    },
  );
}

/// Leaves enough scroll travel to collapse even a short roster on desktop.
/// Extra space stays after the summary, never between identity and players.
class LineupBody extends StatelessWidget {
  const LineupBody({
    super.key,
    required this.child,
    this.collapseExtent = 48,
    this.padding = const EdgeInsets.fromLTRB(8, 4, 8, 8),
  });

  final Widget child;
  final double collapseExtent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) => SliverToBoxAdapter(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: math.max(
            0,
            constraints.viewportMainAxisExtent -
                constraints.precedingScrollExtent +
                collapseExtent,
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class _LineupHeaderDelegate extends SliverPersistentHeaderDelegate {
  _LineupHeaderDelegate({
    required this.homeName,
    required this.awayName,
    required this.homeColor,
    required this.awayColor,
    required this.minimum,
    required this.style,
  });

  final String homeName;
  final String awayName;
  final Color homeColor;
  final Color awayColor;
  final double minimum;
  final TextStyle style;

  @override
  double get minExtent => minimum;
  @override
  double get maxExtent => minimum + 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / 48).clamp(0.0, 1.0);
    final size = 48 - 32 * progress;
    Widget identity(String side, String name, Color color) => Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            key: ValueKey('lineup-$side-badge'),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(name, style: style, softWrap: true)),
        ],
      ),
    );
    return SizedBox.expand(
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              identity('home', homeName, homeColor),
              const SizedBox(width: 8),
              identity('away', awayName, awayColor),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LineupHeaderDelegate oldDelegate) =>
      homeName != oldDelegate.homeName ||
      awayName != oldDelegate.awayName ||
      homeColor != oldDelegate.homeColor ||
      awayColor != oldDelegate.awayColor ||
      minimum != oldDelegate.minimum ||
      style != oldDelegate.style;
}
