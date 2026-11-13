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
    this.homeRanking,
    this.awayRanking,
  });

  final String homeName;
  final String awayName;
  final Color homeColor;
  final Color awayColor;
  final bool stackedIdentity;

  /// Team-total ranking labels shown under the team names in the expanded
  /// stacked header. Collapsing hides them together with the names, leaving
  /// only the pinned color badges. Unused by the default inline variant.
  final String? homeRanking;
  final String? awayRanking;

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
  final theme = Theme.of(context);
  final style = theme.textTheme.titleSmall!;
  final rankingStyle = theme.textTheme.bodySmall!;
  double measure(String name, double available, TextStyle measureStyle) {
    final painter = TextPainter(
      text: TextSpan(text: name, style: measureStyle),
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
  final hasTotals = header.homeRanking != null || header.awayRanking != null;
  final nameHeight = math.max(
    measure(header.homeName, columnWidth, style),
    measure(header.awayName, columnWidth, style),
  );
  final totalHeight = hasTotals
      ? math.max(
          measure(header.homeRanking ?? '', columnWidth, rankingStyle),
          measure(header.awayRanking ?? '', columnWidth, rankingStyle),
        )
      : 0.0;
  // Badge, gap, name and optional totals measured at their final column
  // width; the 16 px collapsed badge always fits the pinned minimum.
  final contentHeight =
      48 + 8 + nameHeight + (hasTotals ? 4 + totalHeight : 0.0);
  return SliverPersistentHeader(
    pinned: true,
    delegate: _StackedIdentityDelegate(
      header: header,
      style: style,
      rankingStyle: rankingStyle,
      minimum: 36,
      expanded: contentHeight + 16,
    ),
  );
}

class _StackedIdentityDelegate extends SliverPersistentHeaderDelegate {
  _StackedIdentityDelegate({
    required this.header,
    required this.style,
    required this.rankingStyle,
    required this.minimum,
    required this.expanded,
  });

  final LineupHeader header;
  final TextStyle style;
  final TextStyle rankingStyle;
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
    // Keep the complete stacked identity only while it fits. A header that
    // cannot show badge, name and totals without cutting reduces to the color
    // badges; the pinned strip never renders intermediate or clipped content.
    final available = math.max(minExtent, maxExtent - shrinkOffset);
    final collapsed =
        available < expanded - 16 || shrinkOffset >= maxExtent - minExtent;
    Widget identity(String side, String name, Color color, String? total) {
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
      if (collapsed) {
        return Expanded(child: Center(child: badge));
      }
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            badge,
            const SizedBox(height: 8),
            Text(name, style: style, textAlign: TextAlign.center),
            if (total != null) ...[
              const SizedBox(height: 4),
              Text(total, style: rankingStyle, textAlign: TextAlign.center),
            ],
          ],
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
              identity(
                'home',
                header.homeName,
                header.homeColor,
                header.homeRanking,
              ),
              const SizedBox(width: 8),
              identity(
                'away',
                header.awayName,
                header.awayColor,
                header.awayRanking,
              ),
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
      rankingStyle != oldDelegate.rankingStyle ||
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
