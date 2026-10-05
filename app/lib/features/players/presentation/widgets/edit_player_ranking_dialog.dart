import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/usecases/update_player_ranking_usecase.dart';

class EditPlayerRankingDialog extends ConsumerStatefulWidget {
  final String playerId;
  final double currentRanking;

  const EditPlayerRankingDialog({
    super.key,
    required this.playerId,
    required this.currentRanking,
  });

  @override
  ConsumerState<EditPlayerRankingDialog> createState() =>
      _EditPlayerRankingDialogState();
}

class _EditPlayerRankingDialogState
    extends ConsumerState<EditPlayerRankingDialog> {
  static final RegExp _allowedChars = RegExp(r'[0-9.,]');

  late final TextEditingController _rankingController;
  late double _rankingValue;
  bool _isLoading = false;
  bool _isUpdatingFromSlider = false;
  bool _isUpdatingFromText = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rankingValue = widget.currentRanking.clamp(0.0, 100.0).toDouble();
    _rankingController = TextEditingController(
      text: _rankingValue.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _rankingController.dispose();
    super.dispose();
  }

  double? _parseRanking(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  void _handleRankingTextChanged(String value) {
    if (_isUpdatingFromSlider || _isUpdatingFromText) {
      return;
    }

    final parsed = _parseRanking(value);
    if (parsed == null) {
      // Still typing (e.g. "12." or an empty field) - keep the last valid
      // value until the input becomes parseable again.
      return;
    }

    final clamped = parsed.clamp(0.0, 100.0).toDouble();

    if (parsed != clamped) {
      // Out of range - clamp and rewrite the field.
      final clampedText = clamped.toStringAsFixed(2);
      setState(() {
        _rankingValue = clamped;
        _isUpdatingFromText = true;
        _rankingController.text = clampedText;
        _rankingController.selection = TextSelection.collapsed(
          offset: clampedText.length,
        );
        _isUpdatingFromText = false;
      });
      return;
    }

    if (clamped == _rankingValue) {
      return;
    }

    setState(() {
      _rankingValue = clamped;
    });
  }

  void _handleSliderChanged(double value) {
    final rounded = (value * 100).round() / 100;
    setState(() {
      _rankingValue = rounded;
      _isUpdatingFromSlider = true;
      _rankingController.text = rounded.toStringAsFixed(2);
      _isUpdatingFromSlider = false;
    });
  }

  Future<void> _submit() async {
    final parsed = _parseRanking(_rankingController.text);
    if (parsed == null) {
      setState(() {
        _error = 'Wprowadź poprawny ranking (0-100).';
      });
      return;
    }

    final newRanking = parsed.clamp(0.0, 100.0).toDouble();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref
          .read(updatePlayerRankingUseCaseProvider)
          .execute(playerId: widget.playerId, newRanking: newRanking);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = (screenWidth - 48).clamp(0.0, 320.0);

    return AlertDialog(
      title: const Text('Edytuj ranking'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: contentWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _rankingController,
                enabled: !_isLoading,
                decoration: const InputDecoration(
                  labelText: 'Nowy ranking',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(_allowedChars),
                ],
                onChanged: _handleRankingTextChanged,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Text(
                'Ranking: ${_rankingValue.toStringAsFixed(2)}',
                style: theme.textTheme.titleMedium,
              ),
              Slider(
                value: _rankingValue,
                min: 0,
                max: 100,
                label: _rankingValue.toStringAsFixed(2),
                onChanged: _isLoading ? null : _handleSliderChanged,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                SelectableText.rich(
                  TextSpan(
                    text: _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Zapisz'),
        ),
      ],
    );
  }
}
