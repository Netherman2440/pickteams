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
    this.stackedIdentity = false,
  });

  final String homeName;
  final String awayName;
  final Color homeColor;
  final Color awayColor;
  final bool stackedIdentity;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      if (stackedIdentity) {
        return _stackedHeader(context, constraints.crossAxisExtent, this);
      }
      final style = Theme.of(context).textTheme.titleSmall!;
      final scaler = MediaQuery.textScalerOf(context);
      // Reserve the largest badge width when measuring so neither transition
      // nor large text can clip a team name.
      double nameHeight(String name) {
        final painter = TextPainter(
          text: TextSpan(text: name, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        );
        try {
          painter.layout(
            maxWidth: math.max(1, (constraints.crossAxisExtent - 24) / 2 - 56),
          );
          return painter.height;
        } finally {
          painter.dispose();
        }
      }

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

Widget _stackedHeader(BuildContext context, double width, LineupHeader header) {
  final style = Theme.of(context).textTheme.titleSmall!;
  double measure(String name, double available) {
    final painter = TextPainter(
      text: TextSpan(text: name, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    try {
      painter.layout(maxWidth: math.max(1, available));
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

  final columnWidth = (width - 24) / 2;
  final inlineHeight = math.max(
    measure(header.homeName, columnWidth - 24),
    measure(header.awayName, columnWidth - 24),
  );
  final stackedHeight = math.max(
    measure(header.homeName, columnWidth),
    measure(header.awayName, columnWidth),
  );
  return SliverPersistentHeader(
    pinned: true,
    delegate: _StackedIdentityDelegate(
      header: header,
      style: style,
      minimum: math.max(36, inlineHeight + 8),
      expanded: 48 + 8 + stackedHeight + 16,
    ),
  );
}

class _StackedIdentityDelegate extends SliverPersistentHeaderDelegate {
  _StackedIdentityDelegate({
    required this.header,
    required this.style,
    required this.minimum,
    required this.expanded,
  });

  final LineupHeader header;
  final TextStyle style;
  final double minimum;
  final double expanded;

  @override
  double get minExtent => minimum;
  @override
  double get maxExtent => math.max(minimum + 48, expanded);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Keep the complete stacked content only while it fits. Switch to the
    // existing inline identity before a shrinking header can cut either item.
    final available = math.max(minExtent, maxExtent - shrinkOffset);
    final collapsed =
        available < expanded - 16 || shrinkOffset >= maxExtent - minExtent;
    Widget identity(String side, String name, Color color) {
      final badge = Container(
        key: ValueKey('lineup-$side-badge'),
        width: collapsed ? 16 : 48,
        height: collapsed ? 16 : 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      );
      final label = Text(name, style: style, textAlign: TextAlign.center);
      return Expanded(
        child: collapsed
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  badge,
                  const SizedBox(width: 8),
                  Flexible(child: label),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [badge, const SizedBox(height: 8), label],
              ),
      );
    }

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: available,
          child: Row(
            children: [
              identity('home', header.homeName, header.homeColor),
              const SizedBox(width: 8),
              identity('away', header.awayName, header.awayColor),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StackedIdentityDelegate oldDelegate) =>
      header != oldDelegate.header ||
      style != oldDelegate.style ||
      minimum != oldDelegate.minimum ||
      expanded != oldDelegate.expanded;
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
