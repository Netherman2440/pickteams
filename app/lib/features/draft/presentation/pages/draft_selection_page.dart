import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/app_config.dart';
import 'package:app/core/app_router.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/presentation/controllers/draft_selection_controller.dart';
import 'package:app/features/draft/presentation/state/draft_selection_state.dart';
import 'package:app/features/draft/presentation/widgets/draft_draggable_player_tile.dart';
import 'package:app/features/draft/presentation/widgets/draft_relation_widgets.dart';
import 'package:app/features/matches/presentation/controllers/create_match_controller.dart';
import 'package:app/features/matches/presentation/controllers/squad_matches_notifier.dart';
import 'package:app/features/players/domain/entities/player.dart';

class DraftSelectionPage extends ConsumerStatefulWidget {
  const DraftSelectionPage({
    super.key,
    required this.squadId,
    this.initialSelectedIds,
    this.initialDraftRules = const [],
    this.matchId,
  });

  final String squadId;
  final List<String>? initialSelectedIds;
  final List<DraftRule> initialDraftRules;
  final String? matchId;

  @override
  ConsumerState<DraftSelectionPage> createState() => _DraftSelectionPageState();
}

class _DraftSelectionPageState extends ConsumerState<DraftSelectionPage> {
  bool _playWithSubstitute = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(draftSelectionControllerProvider.notifier)
          .loadPlayers(
            squadId: widget.squadId,
            initialSelectedIds: widget.initialSelectedIds,
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
        title: const Text('Propozycja - wybór graczy'),
        actions: [
          state.when(
            data: (data) {
              final selectedCount = data.selectedPlayerIds.length;
              final hasMinimumPlayers = selectedCount >= 2;
              final isCreatingMatch = createMatchState.isLoading;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: hasMinimumPlayers && !isCreatingMatch
                          ? () => _generateWithoutRelations(data)
                          : null,
                      child: isCreatingMatch
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Wygeneruj propozycję'),
                    ),
                    TextButton(
                      onPressed: hasMinimumPlayers
                          ? () {
                              final ids = data.selectedPlayerIds.toList(
                                growable: false,
                              );
                              context.pushNamed(
                                AppRoute.draftRelations.name,
                                pathParameters: {'squadId': widget.squadId},
                                extra: {
                                  'selectedIds': ids,
                                  'matchId': widget.matchId,
                                  'playWithSubstitute': _playWithSubstitute,
                                  'draftRules': serializeDraftRules(
                                    data.draftRules,
                                  ),
                                },
                              );
                            }
                          : null,
                      child: const Text('Przejdź do relacji'),
                    ),
                    PopupMenuButton<_SelectionMenuAction>(
                      tooltip: 'Ustawienia propozycji',
                      onSelected: (value) {
                        switch (value) {
                          case _SelectionMenuAction.toggleSubstitute:
                            setState(() {
                              _playWithSubstitute = !_playWithSubstitute;
                            });
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem<_SelectionMenuAction>(
                          enabled: false,
                          child: SizedBox(
                            width: 280,
                            child: Text(
                              'Gra ze zmianami: przy nieparzystej liczbie '
                              'graczy większa drużyna gra ze zmianą.',
                            ),
                          ),
                        ),
                        CheckedPopupMenuItem<_SelectionMenuAction>(
                          value: _SelectionMenuAction.toggleSubstitute,
                          checked: _playWithSubstitute,
                          child: const Text('Gra ze zmianami'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
            error: (_, _) => const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorBody(error: error),
        data: (data) {
          final query = data.searchQuery.trim().toLowerCase();
          bool matchesQuery(Player p) =>
              query.isEmpty || p.name.toLowerCase().contains(query);

          final available = data.players
              .where((p) => !data.selectedPlayerIds.contains(p.playerId))
              .where(matchesQuery)
              .toList(growable: false);

          final selected = data.players
              .where((p) => data.selectedPlayerIds.contains(p.playerId))
              .where(matchesQuery)
              .toList(growable: false);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < AppConfig.compactWidth;

                final selectedPanel = Expanded(
                  flex: isCompact ? 5 : 2,
                  child: _SelectedPlayersPanel(
                    players: selected,
                    selectedCount: data.selectedPlayerIds.length,
                    searchQuery: data.searchQuery,
                    compact: isCompact,
                    onToggle: (playerId) => ref
                        .read(draftSelectionControllerProvider.notifier)
                        .togglePlayer(playerId: playerId),
                    onClear: () => ref
                        .read(draftSelectionControllerProvider.notifier)
                        .clearSelection(),
                  ),
                );

                final availablePanel = Expanded(
                  flex: isCompact ? 4 : 3,
                  child: _AvailablePlayersPanel(
                    players: available,
                    selectedCount: data.selectedPlayerIds.length,
                    searchQuery: data.searchQuery,
                    compact: isCompact,
                    onSearchChanged: (value) => ref
                        .read(draftSelectionControllerProvider.notifier)
                        .setSearchQuery(value),
                    onToggle: (playerId) => ref
                        .read(draftSelectionControllerProvider.notifier)
                        .togglePlayer(playerId: playerId),
                  ),
                );

                return Column(
                  children: [
                    if (data.validationMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _InlineErrorText(
                          message: data.validationMessage!,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          selectedPanel,
                          const SizedBox(height: 12),
                          availablePanel,
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _generateWithoutRelations(DraftSelectionState data) async {
    final ids = data.selectedPlayerIds.toList(growable: false);

    var targetMatchId = widget.matchId;
    if (targetMatchId == null || targetMatchId.isEmpty) {
      final createdMatch = await ref
          .read(createMatchControllerProvider.notifier)
          .createMatch(
            squadId: widget.squadId,
            homePlayers: const <Player>[],
            awayPlayers: const <Player>[],
            rankingHistoryPlayerIds: ids,
          );
      targetMatchId = createdMatch?.matchId;

      if (targetMatchId == null || targetMatchId.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nie udało się utworzyć meczu.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      ref.invalidate(squadMatchesProvider(widget.squadId));
    }

    if (!mounted) {
      return;
    }

    context.pushNamed(
      AppRoute.matchDraft.name,
      pathParameters: {'squadId': widget.squadId, 'matchId': targetMatchId},
      extra: {'selectedIds': ids, 'playWithSubstitute': _playWithSubstitute},
    );
  }
}

class _AvailablePlayersPanel extends StatefulWidget {
  const _AvailablePlayersPanel({
    required this.players,
    required this.selectedCount,
    required this.searchQuery,
    required this.compact,
    required this.onSearchChanged,
    required this.onToggle,
  });

  final List<Player> players;
  final int selectedCount;
  final String searchQuery;
  final bool compact;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onToggle;

  @override
  State<_AvailablePlayersPanel> createState() => _AvailablePlayersPanelState();
}

class _AvailablePlayersPanelState extends State<_AvailablePlayersPanel> {
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final GlobalKey _highlightedTileKey;

  /// Index of the available player currently picked by keyboard
  /// navigation in the search field. `null` means no player is picked, so
  /// Enter adds no one.
  int? _highlightIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _searchController = TextEditingController(text: widget.searchQuery);
    _searchFocusNode = FocusNode(
      debugLabel: 'draft-search-field',
      onKeyEvent: _handleSearchKeyEvent,
    );
    _highlightedTileKey = GlobalKey(debugLabel: 'draft-search-highlight');
  }

  @override
  void didUpdateWidget(covariant _AvailablePlayersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery ||
        widget.searchQuery != _searchController.text) {
      // The query changed: typed in the field or reset externally (e.g.
      // after a state reload). Pick the first match again.
      if (widget.searchQuery != _searchController.text) {
        final target = widget.searchQuery;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _searchController.text != target) {
            _searchController.text = target;
          }
        });
      }
      _highlightIndex = _initialHighlight();
    } else {
      // The list changed but the query did not (e.g. a player was just
      // added): keep the picked position within bounds.
      _highlightIndex = _clampHighlight(_highlightIndex);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int? _initialHighlight() {
    if (widget.searchQuery.trim().isEmpty || widget.players.isEmpty) {
      return null;
    }
    return 0;
  }

  int? _clampHighlight(int? index) {
    if (index == null || widget.players.isEmpty) {
      return null;
    }
    if (index >= widget.players.length) {
      return widget.players.length - 1;
    }
    return index;
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      // Handle the key press once: holding Enter must not add many
      // players.
      if (event is KeyDownEvent) {
        _addHighlightedPlayer();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _moveHighlight(int delta) {
    if (widget.players.isEmpty) {
      return;
    }
    final current = _highlightIndex;
    final next = current == null
        ? (delta > 0 ? 0 : widget.players.length - 1)
        : (current + delta).clamp(0, widget.players.length - 1);
    if (next == current) {
      return;
    }
    setState(() {
      _highlightIndex = next;
    });
    _revealHighlightedTile();
  }

  void _addHighlightedPlayer() {
    final index = _highlightIndex;
    if (index == null || index >= widget.players.length) {
      return;
    }
    final player = widget.players[index];
    widget.onToggle(player.playerId);
    setState(() {
      _highlightIndex = null;
    });
    _searchFocusNode.requestFocus();
    // Select the whole phrase so a single Backspace clears the query.
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  void _revealHighlightedTile() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _highlightedTileKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.4,
          duration: const Duration(milliseconds: 150),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dostępni gracze',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: const InputDecoration(
                labelText: 'Szukaj',
                prefixIcon: Icon(Icons.search),
              ),
              textCapitalization: TextCapitalization.none,
              onChanged: widget.onSearchChanged,
              // The engine turns Enter into a "done" input action
              // whose default behavior unfocuses the field. Hardware
              // keyboards go through [_handleSearchKeyEvent]; software
              // keyboards (no key events for their submit button) only
              // reach this callback. Both route through the same
              // idempotent add path, so the player is added once and
              // the focus stays.
              onEditingComplete: _addHighlightedPlayer,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.players.isEmpty
                  ? Center(
                      child: Text(
                        widget.searchQuery.trim().isEmpty
                            ? 'Brak dostępnych graczy.'
                            : 'Brak dostępnych graczy dla '
                                  '„${widget.searchQuery}”.',
                      ),
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: widget.players.length,
                        itemBuilder: (context, index) {
                          final p = widget.players[index];
                          final isHighlighted = index == _highlightIndex;
                          return DraftDraggablePlayerTile(
                            key: isHighlighted ? _highlightedTileKey : null,
                            player: p,
                            highlighted: isHighlighted,
                            trailing: const Icon(Icons.add_circle_outline),
                            onTap: () => widget.onToggle(p.playerId),
                            dragData: p.playerId,
                            compact: widget.compact,
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedPlayersPanel extends StatefulWidget {
  const _SelectedPlayersPanel({
    required this.players,
    required this.selectedCount,
    required this.searchQuery,
    required this.compact,
    required this.onToggle,
    required this.onClear,
  });

  final List<Player> players;
  final int selectedCount;

  /// Active search phrase; when it is not empty, [players] is already
  /// filtered by it.
  final String searchQuery;
  final bool compact;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  @override
  State<_SelectedPlayersPanel> createState() => _SelectedPlayersPanelState();
}

class _SelectedPlayersPanelState extends State<_SelectedPlayersPanel> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Wybrani gracze (${widget.selectedCount})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: widget.selectedCount == 0 ? null : widget.onClear,
                  child: const Text('Wyczyść'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.players.isEmpty
                  ? Center(
                      child: Text(
                        widget.searchQuery.trim().isEmpty
                            ? 'Nie wybrano jeszcze graczy.'
                            : 'Brak wybranych graczy dla '
                                  '„${widget.searchQuery}”.',
                      ),
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: widget.players.length,
                        itemBuilder: (context, index) {
                          final p = widget.players[index];
                          return DraftDraggablePlayerTile(
                            player: p,
                            trailing: const Icon(Icons.remove_circle_outline),
                            onTap: () => widget.onToggle(p.playerId),
                            dragData: p.playerId,
                            compact: widget.compact,
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
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

enum _SelectionMenuAction { toggleSubstitute }
