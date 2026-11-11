import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/app_config.dart';
import 'package:app/core/app_router.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/presentation/controllers/draft_selection_controller.dart';
import 'package:app/features/draft/presentation/state/draft_selection_state.dart';
import 'package:app/features/draft/presentation/widgets/draft_relation_widgets.dart';
import 'package:app/features/matches/presentation/controllers/create_match_controller.dart';

class DraftAgainstRelationsPage extends ConsumerStatefulWidget {
  const DraftAgainstRelationsPage({
    super.key,
    required this.squadId,
    required this.selectedPlayerIds,
    this.initialDraftRules = const [],
    this.matchId,
    this.playWithSubstitute = true,
  });

  final String squadId;
  final List<String> selectedPlayerIds;
  final List<DraftRule> initialDraftRules;
  final String? matchId;
  final bool playWithSubstitute;

  @override
  ConsumerState<DraftAgainstRelationsPage> createState() =>
      _DraftAgainstRelationsPageState();
}

class _DraftAgainstRelationsPageState
    extends ConsumerState<DraftAgainstRelationsPage> {
  late bool _playWithSubstitute;

  @override
  void initState() {
    super.initState();
    _playWithSubstitute = widget.playWithSubstitute;
    Future.microtask(
      () => ref
          .read(draftSelectionControllerProvider.notifier)
          .loadPlayers(
            squadId: widget.squadId,
            initialSelectedIds: widget.selectedPlayerIds,
            initialRules: widget.initialDraftRules,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(draftSelectionControllerProvider);
    final createMatchState = ref.watch(createMatchControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relacja: Przeciwko'),
        actions: [
          state.when(
            data: (data) {
              final selectedCount = data.selectedPlayerIds.length;
              final hasMinimumPlayers = selectedCount >= 2;
              final hasValidationError = data.validationMessage != null;
              final canGenerate = hasMinimumPlayers && !hasValidationError;
              final isCreatingMatch = createMatchState.isLoading;

              return TextButton(
                onPressed: canGenerate && !isCreatingMatch
                    ? () => _generateDraft(data)
                    : null,
                child: isCreatingMatch
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Wygeneruj propozycje'),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorBody(error: error),
        data: (data) {
          final selected = data.players
              .where(
                (player) => data.selectedPlayerIds.contains(player.playerId),
              )
              .toList(growable: false);
          final playersById = {
            for (final player in selected) player.playerId: player,
          };
          final togetherGroupByPlayer = buildTogetherGroupByPlayer(
            data.togetherGroups,
          );

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wybierz graczy, którzy mają być przeciwko w drużynie.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'W jednej relacji wybierz do ${data.teamCount} graczy.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                if (selected.length >= AppConfig.greedyDraftThresholdPlayers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Uwaga: przy większej liczbie graczy wynik propozycji może być mniej dokładny.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (data.validationMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InlineErrorText(message: data.validationMessage!),
                  ),
                Expanded(
                  child: DraftRelationGroupsList(
                    title: 'Relacje przeciwko',
                    emptyText: 'Brak relacji „Przeciwko sobie”.',
                    groups: data.againstGroups,
                    playersById: playersById,
                    borderColor: Colors.red,
                    onAdd: selected.length < 2
                        ? null
                        : () async {
                            final result = await showDraftRuleEditorDialog(
                              context: context,
                              title: 'Dodaj relację „Przeciwko sobie”',
                              players: selected,
                              blockedPlayerIds: const <String>{},
                              minSelection: 2,
                              maxSelection: data.teamCount,
                              blockTogetherConflicts: true,
                              togetherGroupByPlayer: togetherGroupByPlayer,
                            );
                            if (result == null) {
                              return;
                            }

                            ref
                                .read(draftSelectionControllerProvider.notifier)
                                .upsertAgainstGroup(playerIds: result);
                          },
                    onEdit: (index) async {
                      final initialSelection = data.againstGroups[index];

                      final result = await showDraftRuleEditorDialog(
                        context: context,
                        title: 'Edytuj relację „Przeciwko sobie”',
                        players: selected,
                        blockedPlayerIds: const <String>{},
                        minSelection: 2,
                        maxSelection: data.teamCount,
                        initialSelection: initialSelection,
                        blockTogetherConflicts: true,
                        togetherGroupByPlayer: togetherGroupByPlayer,
                      );
                      if (result == null) {
                        return;
                      }

                      ref
                          .read(draftSelectionControllerProvider.notifier)
                          .upsertAgainstGroup(playerIds: result, index: index);
                    },
                    onDelete: (index) => ref
                        .read(draftSelectionControllerProvider.notifier)
                        .removeAgainstGroup(index),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _generateDraft(DraftSelectionState data) async {
    final validationMessage = ref
        .read(draftSelectionControllerProvider.notifier)
        .validateSelection();
    if (validationMessage != null) {
      return;
    }

    final ids = data.selectedPlayerIds.toList(growable: false);

    final targetMatchId = widget.matchId;
    final existing = targetMatchId != null && targetMatchId.isNotEmpty;
    context.pushNamed(
      existing ? AppRoute.matchDraft.name : AppRoute.draftPreview.name,
      pathParameters: {
        'squadId': widget.squadId,
        if (existing) 'matchId': targetMatchId,
      },
      extra: {
        'selectedIds': ids,
        'playWithSubstitute': _playWithSubstitute,
        'draftRules': serializeDraftRules(data.draftRules),
      },
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final err = error;
    final message = err is Failure ? err.message : err.toString();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SelectableText.rich(
        TextSpan(
          text: message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

class _InlineErrorText extends StatelessWidget {
  const _InlineErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(
        text: message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
