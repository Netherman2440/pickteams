import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../application/dto/player_dto.dart';

TextStyle _nameStyle(BuildContext context) => DefaultTextStyle.of(context).style
    .merge(Theme.of(context).textTheme.bodyMedium)
    .copyWith(fontSize: 14, height: 1.35);

TextStyle _rankingStyle(BuildContext context) => DefaultTextStyle.of(context)
    .style
    .merge(Theme.of(context).textTheme.bodySmall)
    .copyWith(fontSize: 12, height: 1.35);

/// The sliver supplies spare viewport space, not an intrinsic-height constraint.
class MatchViewRoster extends StatelessWidget {
  const MatchViewRoster({
    super.key,
    required this.home,
    required this.away,
    required this.onPlayerTap,
    required this.footer,
    required this.gap,
  });

  final List<PlayerDto> home;
  final List<PlayerDto> away;
  final ValueChanged<PlayerDto> onPlayerTap;
  final Widget footer;
  final double gap;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final count = math.max(home.length, away.length);
      final teams = [
        [...home]..sort((a, b) => b.ranking.compareTo(a.ranking)),
        [...away]..sort((a, b) => b.ranking.compareTo(a.ranking)),
      ];
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: MatchViewRosterLayout(
            rowCount: count,
            gap: gap,
            minimumRowHeight:
                MediaQuery.textScalerOf(context).scale(14) * 1.35 * 2 + 16,
            minimumHeight: math.max(
              0,
              constraints.viewportMainAxisExtent -
                  constraints.precedingScrollExtent -
                  12,
            ),
            children: [
              for (var index = 0; index < count; index++)
                for (final team in teams)
                  if (index < team.length)
                    MatchViewPlayerPanel(
                      player: team[index],
                      onTap: () => onPlayerTap(team[index]),
                    )
                  else
                    const SizedBox.shrink(),
              footer,
            ],
          ),
        ),
      );
    },
  );
}

/// Row-major panel pairs followed by one footer, inside a vertical sliver.
/// Measure the real children at their final widths with no height limit first.
/// Only then give every panel the common height and place the footer after them.
class MatchViewRosterLayout extends MultiChildRenderObjectWidget {
  const MatchViewRosterLayout({
    super.key,
    required this.rowCount,
    required this.gap,
    required this.minimumRowHeight,
    required this.minimumHeight,
    required super.children,
  }) : assert(rowCount >= 0),
       assert(gap >= 0),
       assert(minimumRowHeight >= 0),
       assert(minimumHeight >= 0);

  final int rowCount;
  final double gap;
  final double minimumRowHeight;
  final double minimumHeight;

  @override
  RenderMatchViewRoster createRenderObject(BuildContext context) =>
      RenderMatchViewRoster(rowCount, gap, minimumRowHeight, minimumHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMatchViewRoster renderObject,
  ) => renderObject.configure(rowCount, gap, minimumRowHeight, minimumHeight);
}

class _RosterParentData extends ContainerBoxParentData<RenderBox> {}

class RenderMatchViewRoster extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  RenderMatchViewRoster(
    this._rowCount,
    this._gap,
    this._minimumRowHeight,
    this._minimumHeight,
  );

  int _rowCount;
  double _gap;
  double _minimumRowHeight;
  double _minimumHeight;

  void configure(int rows, double gap, double rowHeight, double height) {
    if (_rowCount == rows &&
        _gap == gap &&
        _minimumRowHeight == rowHeight &&
        _minimumHeight == height) {
      return;
    }
    _rowCount = rows;
    _gap = gap;
    _minimumRowHeight = rowHeight;
    _minimumHeight = height;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _RosterParentData();
    }
  }

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth && !constraints.hasBoundedHeight);
    assert(childCount == _rowCount * 2 + 1);
    final width = constraints.maxWidth;
    final columnWidth = math.max(0.0, (width - _gap) / 2);
    final footer = lastChild!;
    footer.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    var rowHeight = _minimumRowHeight;
    for (var child = firstChild; child != footer; child = childAfter(child)) {
      child!.layout(
        BoxConstraints.tightFor(width: columnWidth),
        parentUsesSize: true,
      );
      rowHeight = math.max(rowHeight, child.size.height);
    }
    if (_rowCount > 0) {
      rowHeight = math.max(
        rowHeight,
        (_minimumHeight - footer.size.height) / _rowCount,
      );
    }
    var index = 0;
    for (var child = firstChild; child != footer; child = childAfter(child)) {
      child!.layout(
        BoxConstraints.tightFor(width: columnWidth, height: rowHeight),
        parentUsesSize: true,
      );
      (child.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
        index.isEven ? 0 : columnWidth + _gap,
        (index ~/ 2) * rowHeight,
      );
      index++;
    }
    final footerTop = math.max(
      _rowCount * rowHeight,
      _minimumHeight - footer.size.height,
    );
    (footer.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      0,
      footerTop,
    );
    size = constraints.constrain(Size(width, footerTop + footer.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class MatchViewPlayerPanel extends StatelessWidget {
  const MatchViewPlayerPanel({
    super.key,
    required this.player,
    required this.onTap,
  });

  final PlayerDto player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(14) * 1.35 * 2 + 16,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text(player.name, style: _nameStyle(context))),
          const SizedBox(width: 8),
          Text(
            player.ranking.toStringAsFixed(2),
            style: _rankingStyle(context),
          ),
        ],
      ),
    ),
  );
}
