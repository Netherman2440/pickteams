import 'package:flutter/material.dart';

class ProbabilitySlider extends StatelessWidget {
  const ProbabilitySlider({
    super.key,
    required this.homeColor,
    required this.awayColor,
    required this.homeProbability,
    this.title = 'Szansa na wygraną',
    this.infoText,
    this.animationDuration = const Duration(milliseconds: 350),
  });

  final Color homeColor;
  final Color awayColor;
  final double homeProbability;
  final String title;
  final String? infoText;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = homeProbability.isNaN
        ? 0.5
        : homeProbability.clamp(0.0, 1.0);
    final homePercent = (clamped * 100).round();
    final awayPercent = 100 - homePercent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                if (infoText != null)
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    tooltip: 'Jak to obliczamy?',
                    onPressed: () => _showInfo(context, infoText!, title),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('$homePercent%'), Text('$awayPercent%')],
            ),
            const SizedBox(height: 8),
            _AnimatedBar(
              homeColor: homeColor,
              awayColor: awayColor,
              homeProbability: clamped,
              animationDuration: animationDuration,
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context, String message, String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zamknij'),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  const _AnimatedBar({
    required this.homeColor,
    required this.awayColor,
    required this.homeProbability,
    required this.animationDuration,
  });

  final Color homeColor;
  final Color awayColor;
  final double homeProbability;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 12,
            child: Stack(
              children: [
                Container(color: awayColor),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: homeProbability),
                  duration: animationDuration,
                  builder: (context, value, child) {
                    final width = constraints.maxWidth * value;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(width: width, color: homeColor),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
