import 'package:flutter/material.dart';

import 'package:app/features/players/domain/entities/player.dart';

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueSemanticsLabel,
    this.maxValueWidthFraction,
  });

  final String label;
  final Object? value;
  final Color? valueColor;
  final String? valueSemanticsLabel;
  final double? maxValueWidthFraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueText = _formatValue(value);

    final trailing = Text(
      valueText,
      style: theme.textTheme.titleMedium?.copyWith(color: valueColor),
      semanticsLabel: valueSemanticsLabel,
      textAlign: TextAlign.right,
    );
    Widget tile(Widget value) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(label),
      trailing: value,
    );
    if (maxValueWidthFraction == null) return tile(trailing);
    return LayoutBuilder(
      builder: (context, constraints) => tile(
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * maxValueWidthFraction!,
          ),
          child: trailing,
        ),
      ),
    );
  }

  String _formatValue(Object? value) {
    if (value == null) {
      return '-';
    }
    if (value is Player) {
      return value.name;
    }
    if (value is num) {
      final number = value.toDouble();
      if ((number - number.roundToDouble()).abs() < 0.0001) {
        return number.toInt().toString();
      }
      return number.toStringAsFixed(2);
    }
    return value.toString();
  }
}
