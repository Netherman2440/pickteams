import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/app_config.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/core/app_router.dart';
import 'package:app/features/players/application/usecases/delete_player_usecase.dart';
import 'package:app/features/players/domain/entities/player_position.dart';
import 'package:app/features/players/presentation/controllers/players_notifier.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';

import '../controllers/player_details_controller.dart';
import '../widgets/edit_player_position_dialog.dart';
import '../widgets/ranking_history_graph_widget.dart';
import '../widgets/edit_player_name_dialog.dart';
import '../widgets/edit_player_ranking_dialog.dart';

class PlayerDetailsPage extends ConsumerStatefulWidget {
  final String squadId;
  final String playerId;

  const PlayerDetailsPage({
    super.key,
    required this.squadId,
    required this.playerId,
  });

  @override
  ConsumerState<PlayerDetailsPage> createState() => _PlayerDetailsPageState();
}

class _PlayerDetailsPageState extends ConsumerState<PlayerDetailsPage> {
  bool _editing = false;
  String get squadId => widget.squadId;
  String get playerId => widget.playerId;

  @override
  void didUpdateWidget(covariant PlayerDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerId != playerId || oldWidget.squadId != squadId) {
      _editing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(playerDetailsProvider(playerId));
    final squadAsync = ref.watch(squadDetailProvider(squadId));
    final role = squadAsync.maybeWhen(
      data: (squad) => squad.role,
      orElse: () => SquadRole.none,
    );
    final canEdit = role == SquadRole.owner || role == SquadRole.admin;
    if (!canEdit) _editing = false;
    final playerName = stateAsync.maybeWhen(
      data: (state) => state.player.name,
      orElse: () => null,
    );
    final title = 'Szczegóły gracza';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          if (canEdit && playerName != null)
            IconButton(
              tooltip: 'Usuń gracza',
              icon: const Icon(Icons.delete),
              color: Colors.red,
              onPressed: () => _confirmDeletePlayer(
                context,
                ref,
                squadId: squadId,
                playerId: playerId,
                playerName: playerName,
              ),
            ),
        ],
      ),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: SelectableText.rich(
            TextSpan(
              text: 'Błąd: ${err.toString()}',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
        data: (state) {
          final player = state.player;
          final history = state.rankingHistory;
          final difference = player.ranking - player.baseRanking;
          final isPositive = difference >= 0;
          final positionLabel =
              playerPositionPolishLabel(player.position) ?? 'Brak pozycji';
          final isNarrowScreen =
              MediaQuery.sizeOf(context).width < AppConfig.mobileWidth;
          final baseNameStyle =
              Theme.of(context).textTheme.headlineMedium ??
              const TextStyle(fontSize: 28);
          final nameStyle = isNarrowScreen
              ? baseNameStyle.copyWith(
                  fontSize: ((baseNameStyle.fontSize ?? 28) * 0.8)
                      .clamp(18.0, 24.0)
                      .toDouble(),
                  height: 1.1,
                )
              : baseNameStyle;

          final fields = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EditableProfileField(
                label: 'Edytuj nazwę',
                onTap: _editing
                    ? () => _editField(
                        EditPlayerNameDialog(
                          playerId: playerId,
                          initialName: player.name,
                        ),
                      )
                    : null,
                child: Text(player.name, style: nameStyle, softWrap: true),
              ),
              const SizedBox(height: 8),
              _EditableProfileField(
                label: 'Edytuj ranking',
                onTap: _editing
                    ? () => _editField(
                        EditPlayerRankingDialog(
                          playerId: playerId,
                          currentRanking: player.ranking,
                        ),
                      )
                    : null,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Ranking: ${player.ranking.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    _RankingDifferenceIndicator(
                      difference: difference,
                      isPositive: isPositive,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _EditableProfileField(
                label: 'Edytuj pozycję',
                onTap: _editing
                    ? () => _editField(
                        EditPlayerPositionDialog(
                          playerId: playerId,
                          initialPosition: player.position,
                        ),
                      )
                    : null,
                child: Text(
                  'Pozycja: $positionLabel',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          );
          final avatar = CircleAvatar(
            radius: 40,
            child: Text(
              player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 32),
            ),
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canEdit) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _editing = !_editing),
                      icon: Icon(_editing ? Icons.check : Icons.edit),
                      label: Text(_editing ? 'Gotowe' : 'Edytuj gracza'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (isNarrowScreen) ...[
                  avatar,
                  const SizedBox(height: 16),
                  fields,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(width: 24),
                      Expanded(child: fields),
                    ],
                  ),
                const SizedBox(height: 24),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Historia rankingu',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Historia rankingu'),
                          content: const Text(
                            'Po każdym meczu ranking gracza jest aktualizowany automatycznie. '
                            'Im większa różnica bramek, tym większa zmiana rankingu '
                            '(w górę lub w dół).',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: RankingHistoryGraphWidget(
                      history: history,
                      baseRanking: player.baseRanking.toDouble(),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _PlayerTabs(squadId: squadId, playerId: playerId),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _editField(Widget dialog) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => dialog,
    );
    if (result == true && mounted) {
      ref.invalidate(playerDetailsProvider(playerId));
    }
  }

  Future<void> _confirmDeletePlayer(
    BuildContext context,
    WidgetRef ref, {
    required String squadId,
    required String playerId,
    required String playerName,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć gracza?'),
        content: Text(
          'To trwale usunie '
          '${playerName.isNotEmpty ? playerName : 'tego gracza'} '
          'ze składu. Tej operacji nie można cofnąć.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(deletePlayerUseCaseProvider).execute(playerId: playerId);
      await ref
          .read(playersNotifierProvider.notifier)
          .refreshPlayers(squadId: squadId);
      if (context.mounted) {
        context.pop();
      }
    } catch (error) {
      if (!context.mounted) return;
      final message = error is Failure ? error.message : error.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
    }
  }
}

/// Only edit mode exposes a focusable button; the whole region is its target.
class _EditableProfileField extends StatelessWidget {
  const _EditableProfileField({
    required this.label,
    required this.child,
    this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
    if (onTap == null) return content;
    final border = BorderRadius.circular(8);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        shape: RoundedRectangleBorder(
          borderRadius: border,
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(onTap: onTap, borderRadius: border, child: content),
      ),
    );
  }
}

class _RankingDifferenceIndicator extends StatelessWidget {
  final double difference;
  final bool isPositive;

  const _RankingDifferenceIndicator({
    required this.difference,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    if (difference.abs() < 0.01) return const SizedBox.shrink();

    final color = isPositive ? Colors.green : Colors.red;
    final icon = isPositive ? Icons.arrow_upward : Icons.arrow_downward;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 4),
        Text(
          difference.abs().toStringAsFixed(2),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _PlayerTabs extends StatelessWidget {
  final String squadId;
  final String playerId;

  const _PlayerTabs({required this.squadId, required this.playerId});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 16,
          runSpacing: 16,
          children: [
            _TabButton(
              label: 'Mecze',
              icon: Icons.sports_soccer,
              onPressed: () => context.pushNamed(
                AppRoute.playerMatches.name,
                pathParameters: {'squadId': squadId, 'playerId': playerId},
              ),
            ),
            _TabButton(
              label: 'Turnieje',
              icon: Icons.emoji_events,
              onPressed: () => context.pushNamed(
                AppRoute.playerTournaments.name,
                pathParameters: {'squadId': squadId, 'playerId': playerId},
              ),
            ),
            _TabButton(
              label: 'Statystyki',
              icon: Icons.analytics,
              onPressed: () => context.pushNamed(
                AppRoute.playerStats.name,
                pathParameters: {'squadId': squadId, 'playerId': playerId},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 32,
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}
