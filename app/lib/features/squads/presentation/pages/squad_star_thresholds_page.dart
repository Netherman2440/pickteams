import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/matches/application/match_level_providers.dart';
import 'package:app/features/matches/application/save_star_thresholds.dart';
import 'package:app/features/matches/domain/match_level.dart';
import '../../domain/entities/user_squad_role.dart';
import '../state/squad_detail_notifier.dart';

class SquadStarThresholdsPage extends ConsumerStatefulWidget {
  const SquadStarThresholdsPage({super.key, required this.squadId});
  final String squadId;

  @override
  ConsumerState<SquadStarThresholdsPage> createState() =>
      _SquadStarThresholdsPageState();
}

class _SquadStarThresholdsPageState
    extends ConsumerState<SquadStarThresholdsPage> {
  final _fields = List.generate(5, (_) => TextEditingController());
  bool _initialized = false;
  bool _saving = false;
  String? _message;

  @override
  void didUpdateWidget(covariant SquadStarThresholdsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.squadId != widget.squadId) {
      _initialized = false;
      _message = null;
      for (final field in _fields) {
        field.clear();
      }
    }
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  MatchLevelThresholds? get _draft {
    try {
      return MatchLevelThresholds(
        _fields.map((f) => double.parse(f.text.trim().replaceAll(',', '.'))),
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await SaveStarThresholds(ref.read(matchLevelRepositoryProvider)).execute(
        squadId: widget.squadId,
        role: ref.read(squadDetailProvider(widget.squadId)).asData?.value.role,
        values: draft.full,
      );
      ref.invalidate(starThresholdsProvider(widget.squadId));
      if (mounted) setState(() => _message = 'Zapisano progi gwiazdek.');
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Nie udało się zapisać progów. Spróbuj ponownie.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final squad = ref.watch(squadDetailProvider(widget.squadId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progi gwiazdek'),
        leading: IconButton(
          tooltip: 'Powrót do ustawień',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed(
                AppRoute.settings.name,
                pathParameters: {'squadId': widget.squadId},
              );
            }
          },
        ),
      ),
      body: SafeArea(
        child: squad.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Nie udało się wczytać składu.')),
          data: (squad) {
            if (squad.role != SquadRole.owner) {
              return const Center(child: Text('Brak uprawnień.'));
            }
            final settings = ref.watch(starThresholdsProvider(widget.squadId));
            return settings.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Nie udało się wczytać progów.'),
                    TextButton(
                      onPressed: () => ref.invalidate(
                        starThresholdsProvider(widget.squadId),
                      ),
                      child: const Text('Spróbuj ponownie'),
                    ),
                  ],
                ),
              ),
              data: (thresholds) {
                if (!_initialized) {
                  for (var i = 0; i < 5; i++) {
                    _fields[i].text =
                        thresholds?.full[i].toString().replaceAll('.', ',') ??
                        '';
                  }
                  _initialized = true;
                }
                final draft = _draft;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Pięć progów pełnych gwiazdek musi być liczbowych i ściśle rosnących. Połówki wyliczamy automatycznie w połowie sąsiednich progów.',
                          ),
                          const SizedBox(height: 12),
                          if (thresholds == null)
                            const Text(
                              'Progi nie są skonfigurowane. Gwiazdki pozostają ukryte do zapisu progów i rozegrania ponad 25 zakończonych meczów. Brak skalibrowanych wartości domyślnych.',
                            ),
                          for (var i = 0; i < 5; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: TextField(
                                controller: _fields[i],
                                enabled: !_saving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: '${i + 1} — próg pełnych gwiazdek',
                                  prefixIcon: const Icon(Icons.star),
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) =>
                                    setState(() => _message = null),
                              ),
                            ),
                          const SizedBox(height: 8),
                          const Text('Automatyczne połówki'),
                          for (var i = 0; i < 4; i++)
                            Row(
                              children: [
                                const Icon(Icons.star_half, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  '${i + 1},5: ${draft == null ? '—' : draft.halves[i].toString().replaceAll('.', ',')}',
                                ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          if (draft == null)
                            const Text(
                              'Wpisz pięć skończonych wartości w kolejności rosnącej.',
                            ),
                          if (_message != null)
                            Semantics(liveRegion: true, child: Text(_message!)),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: draft == null || _saving ? null : _save,
                            child: Text(_saving ? 'Zapisywanie…' : 'Zapisz'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
