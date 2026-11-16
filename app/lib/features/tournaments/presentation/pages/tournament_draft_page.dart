import 'dart:math';
import 'package:app/core/utils/team_ranking.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:app/core/app_config.dart';
import 'package:app/core/app_router.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/features/draft/application/create_draft_use_case.dart';
import 'package:app/features/draft/application/get_player_pair_win_rates_use_case.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/domain/entities/head_to_head_win_rate.dart';
import 'package:app/features/draft/domain/services/draft_algorithm_policy.dart';
import 'package:app/features/draft/presentation/widgets/draft_draggable_player_tile.dart';
import 'package:app/features/players/application/usecases/get_squad_players_usecase.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:app/features/tournaments/application/usecases/accept_tournament_draft_usecase.dart';
import 'package:app/features/tournaments/application/usecases/get_tournament_draft_usecase.dart';
import 'package:app/features/tournaments/application/usecases/save_tournament_draft_usecase.dart';
import 'package:app/features/tournaments/application/usecases/update_tournament_teams_usecase.dart';
import 'package:app/features/tournaments/application/restore_tournament_drafts.dart';
import 'package:app/features/tournaments/domain/entities/tournament_team.dart';
import 'package:app/features/tournaments/presentation/state/tournament_providers.dart';
import 'package:app/features/tournaments/tournaments_providers.dart';

class TournamentDraftPage extends ConsumerStatefulWidget {
  const TournamentDraftPage({
    super.key,
    required this.squadId,
    required this.tournamentId,
    this.selectedPlayerIds = const [],
    this.teamCount = 2,
    this.draftRules = const [],
    this.tournamentDraftId,
  });

  final String squadId;
  final String tournamentId;
  final List<String> selectedPlayerIds;
  final int teamCount;
  final List<DraftRule> draftRules;
  final String? tournamentDraftId;

  @override
  ConsumerState<TournamentDraftPage> createState() =>
      _TournamentDraftPageState();
}

class _TournamentDraftPageState extends ConsumerState<TournamentDraftPage> {
  bool _isLoading = true;
  bool _isAccepting = false;
  String? _error;
  String? _draftId;
  int _selectedIndex = 0;
  List<Draft> _proposals = const [];
  List<List<Player>> _currentTeams = const [];
  final Map<int, List<List<Player>>> _editedTeamsByProposal = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedIndex = 0;
      _currentTeams = const [];
      _editedTeamsByProposal.clear();
    });

    try {
      if (widget.tournamentDraftId != null &&
          widget.tournamentDraftId!.isNotEmpty) {
        await _loadStoredDraft(widget.tournamentDraftId!);
      } else {
        await _generateDraft();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error is Failure ? error.message : error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadStoredDraft(String draftId) async {
    final draft = await ref
        .read(getTournamentDraftUseCaseProvider)
        .execute(tournamentDraftId: draftId);

    if (draft == null) {
      throw const NotFoundFailure('Nie znaleziono draftu turnieju.');
    }

    if (draft.status == 'error') {
      throw ValidationFailure(
        draft.errorMessage ??
            'Generowanie propozycji wcześniej się nie powiodło.',
      );
    }

    final players = await ref
        .read(getSquadPlayersUseCaseProvider)
        .execute(squadId: widget.squadId);

    final playersById = {for (final player in players) player.playerId: player};
    final proposals = restoreTournamentDrafts(
      proposals: draft.proposals,
      playersById: playersById,
    );

    _setDraftData(proposals: proposals, draftId: draft.tournamentDraftId);
  }

  Future<void> _generateDraft() async {
    final selectedIds = widget.selectedPlayerIds.toSet().toList(
      growable: false,
    );
    if (selectedIds.length < widget.teamCount) {
      throw ValidationFailure(
        'Losowanie wymaga co najmniej ${widget.teamCount} wybranych graczy.',
      );
    }

    final players = await ref
        .read(getSquadPlayersUseCaseProvider)
        .execute(squadId: widget.squadId);

    final selectedPlayers = players
        .where((player) => selectedIds.contains(player.playerId))
        .toList(growable: false);

    final algorithm = DraftAlgorithmPolicy.resolve(
      teamCount: widget.teamCount,
      playerCount: selectedPlayers.length,
    );

    final createDraftUseCase = switch (algorithm) {
      DraftAlgorithmSelection.combinatory => ref.read(
        combinatoryCreateDraftUseCaseProvider,
      ),
      DraftAlgorithmSelection.greedy => ref.read(
        greedyCreateDraftUseCaseProvider,
      ),
    };

    final seed = algorithm == DraftAlgorithmSelection.greedy
        ? Random().nextInt(0x7FFFFFFF)
        : null;

    final proposals = await createDraftUseCase.execute(
      players: selectedPlayers,
      teamCount: widget.teamCount,
      rules: widget.draftRules,
      seed: seed,
    );

    final winRates = await ref
        .read(getPlayerPairWinRatesUseCaseProvider)
        .execute(playerIds: selectedIds);

    final winRateMatrix = _buildWinRateMatrix(winRates);

    final draftId = await ref
        .read(saveTournamentDraftUseCaseProvider)
        .executeCompleted(
          squadId: widget.squadId,
          tournamentId: widget.tournamentId,
          selectedPlayerIds: selectedIds,
          teamCount: widget.teamCount,
          rules: widget.draftRules,
          proposals: proposals,
          winRateMatrix: winRateMatrix,
          seed: seed,
        );

    _setDraftData(proposals: proposals, draftId: draftId);
  }

  void _setDraftData({
    required List<Draft> proposals,
    required String draftId,
  }) {
    final initialTeams = proposals.isEmpty
        ? const <List<Player>>[]
        : _teamsFromDraft(proposals.first);

    setState(() {
      _draftId = draftId;
      _proposals = proposals;
      _selectedIndex = 0;
      _currentTeams = _cloneTeams(initialTeams);
      _editedTeamsByProposal
        ..clear()
        ..[0] = _cloneTeams(initialTeams);
    });
  }

  void _selectProposal(int nextIndex) {
    if (nextIndex < 0 || nextIndex >= _proposals.length) {
      return;
    }
    if (_selectedIndex == nextIndex) {
      return;
    }

    setState(() {
      _editedTeamsByProposal[_selectedIndex] = _cloneTeams(_currentTeams);
      _selectedIndex = nextIndex;

      final cachedTeams = _editedTeamsByProposal[nextIndex];
      _currentTeams = cachedTeams != null
          ? _cloneTeams(cachedTeams)
          : _teamsFromDraft(_proposals[nextIndex]);
      _editedTeamsByProposal[nextIndex] = _cloneTeams(_currentTeams);
    });
  }

  void _movePlayer({required String playerId, required int toTeamIndex}) {
    if (toTeamIndex < 0 || toTeamIndex >= _currentTeams.length) {
      return;
    }

    final fromTeamIndex = _currentTeams.indexWhere(
      (team) => team.any((player) => player.playerId == playerId),
    );

    if (fromTeamIndex < 0 || fromTeamIndex == toTeamIndex) {
      return;
    }

    final player = _currentTeams[fromTeamIndex].firstWhere(
      (item) => item.playerId == playerId,
    );

    setState(() {
      _currentTeams[fromTeamIndex].removeWhere(
        (item) => item.playerId == playerId,
      );
      _currentTeams[toTeamIndex].add(player);
      _editedTeamsByProposal[_selectedIndex] = _cloneTeams(_currentTeams);
    });
  }

  Future<void> _acceptProposal() async {
    final draftId = _draftId;
    if (draftId == null) {
      return;
    }

    final proposalIndex = _selectedIndex;

    setState(() {
      _isAccepting = true;
      _error = null;
      _editedTeamsByProposal[_selectedIndex] = _cloneTeams(_currentTeams);
    });

    try {
      await ref
          .read(acceptTournamentDraftUseCaseProvider)
          .execute(
            tournamentId: widget.tournamentId,
            tournamentDraftId: draftId,
            proposalIndex: proposalIndex,
          );

      await _applyManualTeamChangesIfNeeded(proposalIndex: proposalIndex);

      if (!mounted) {
        return;
      }

      ref.invalidate(tournamentDetailsProvider(widget.tournamentId));
      ref.invalidate(squadTournamentsProvider(widget.squadId));

      context.goNamed(
        AppRoute.tournamentDetails.name,
        pathParameters: {
          'squadId': widget.squadId,
          'tournamentId': widget.tournamentId,
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error is Failure ? error.message : error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
        });
      }
    }
  }

  Future<void> _applyManualTeamChangesIfNeeded({
    required int proposalIndex,
  }) async {
    if (!_hasManualChanges(proposalIndex)) {
      return;
    }

    final editedTeams = _editedTeamsByProposal[proposalIndex];
    if (editedTeams == null || editedTeams.isEmpty) {
      return;
    }

    final existingTeams = await ref
        .read(tournamentRepositoryProvider)
        .getTournamentTeams(tournamentId: widget.tournamentId);

    if (existingTeams.length < editedTeams.length) {
      throw const ValidationFailure(
        'Nie udało się dopasować edytowanych drużyn do drużyn turnieju.',
      );
    }

    final teamInputs = <TournamentTeamInput>[];
    for (var index = 0; index < editedTeams.length; index++) {
      final existing = existingTeams[index];
      final playerIds = editedTeams[index]
          .map((player) => player.playerId)
          .toList(growable: false);

      teamInputs.add(
        TournamentTeamInput(
          tournamentTeamId: existing.tournamentTeamId,
          name: existing.name,
          color: existing.color,
          playerIds: playerIds,
        ),
      );
    }

    await ref
        .read(updateTournamentTeamsUseCaseProvider)
        .execute(tournamentId: widget.tournamentId, teams: teamInputs);
  }

  bool _hasManualChanges(int proposalIndex) {
    if (proposalIndex < 0 || proposalIndex >= _proposals.length) {
      return false;
    }

    final edited = _editedTeamsByProposal[proposalIndex];
    if (edited == null) {
      return false;
    }

    final originalIds = _teamPlayerIdsFromDraft(_proposals[proposalIndex]);
    final editedIds = _teamPlayerIds(edited);

    return !_sameTeamAssignments(originalIds, editedIds);
  }

  @override
  Widget build(BuildContext context) {
    final squadAsync = ref.watch(squadDetailProvider(widget.squadId));
    final canManage =
        squadAsync.asData?.value.role == SquadRole.owner ||
        squadAsync.asData?.value.role == SquadRole.admin;
    final canAccept =
        canManage && !_isLoading && _error == null && _proposals.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Propozycje turnieju'),
        actions: [
          if (canAccept)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _isAccepting ? null : _acceptProposal,
                child: _isAccepting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Zakceptuj propozycję'),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (widget.tournamentDraftId == null)
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Spróbuj ponownie'),
                      ),
                  ],
                ),
              ),
            )
          : _proposals.isEmpty
          ? const Center(child: Text('Brak wygenerowanych propozycji.'))
          : Column(
              children: [
                const SizedBox(height: 12),
                _ProposalNavigator(
                  index: _selectedIndex,
                  total: _proposals.length,
                  onPrev: _selectedIndex > 0
                      ? () => _selectProposal(_selectedIndex - 1)
                      : null,
                  onNext: _selectedIndex < _proposals.length - 1
                      ? () => _selectProposal(_selectedIndex + 1)
                      : null,
                ),
                if (canManage) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Przeciągnij zawodników między drużynami.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: _ProposalTeamsView(
                    teams: _currentTeams,
                    playWithSubstitute:
                        _proposals[_selectedIndex].playWithSubstitute,
                    onMovePlayer: canManage
                        ? (playerId, teamIndex) {
                            _movePlayer(
                              playerId: playerId,
                              toTeamIndex: teamIndex,
                            );
                          }
                        : null,
                  ),
                ),
              ],
            ),
    );
  }
}

class _ProposalNavigator extends StatelessWidget {
  const _ProposalNavigator({
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
        Text('Propozycja ${index + 1} / $total'),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class _ProposalTeamsView extends StatelessWidget {
  const _ProposalTeamsView({
    required this.teams,
    required this.onMovePlayer,
    required this.playWithSubstitute,
  });

  final bool playWithSubstitute;
  final List<List<Player>> teams;
  final void Function(String playerId, int teamIndex)? onMovePlayer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (teams.isEmpty) {
          return const Center(child: Text('Brak dostępnych drużyn.'));
        }

        final isCompact = constraints.maxWidth < AppConfig.compactWidth;
        const spacing = 12.0;
        const minTileWidth = 240.0;
        final maxColumns = min(4, teams.length);

        final columns = isCompact
            ? 1
            : ((constraints.maxWidth + spacing) / (minTileWidth + spacing))
                  .floor()
                  .clamp(1, maxColumns);

        final cardWidth = isCompact
            ? constraints.maxWidth
            : (constraints.maxWidth - (columns - 1) * spacing) / columns;

        final cards = [
          for (var i = 0; i < teams.length; i++)
            SizedBox(
              width: cardWidth,
              child: _TeamProposalCard(
                teamIndex: i,
                players: teams[i],
                compact: isCompact,
                playWithSubstitute: playWithSubstitute,
                opponentSize: teams.map((team) => team.length).reduce(min),
                onAcceptPlayerId: onMovePlayer == null
                    ? null
                    : (playerId) => onMovePlayer!(playerId, i),
              ),
            ),
        ];

        if (isCompact) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => cards[index],
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: spacing, runSpacing: spacing, children: cards),
        );
      },
    );
  }
}

class _TeamProposalCard extends StatelessWidget {
  const _TeamProposalCard({
    required this.teamIndex,
    required this.players,
    required this.compact,
    required this.playWithSubstitute,
    required this.opponentSize,
    required this.onAcceptPlayerId,
  });

  final int teamIndex;
  final List<Player> players;
  final bool compact;
  final bool playWithSubstitute;
  final int opponentSize;
  final ValueChanged<String>? onAcceptPlayerId;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: onAcceptPlayerId == null
          ? null
          : (details) {
              final playerId = _extractPlayerId(details.data);
              if (playerId == null) {
                return false;
              }

              return !players.any((player) => player.playerId == playerId);
            },
      onAcceptWithDetails: onAcceptPlayerId == null
          ? null
          : (details) {
              final playerId = _extractPlayerId(details.data);
              if (playerId == null) {
                return;
              }
              onAcceptPlayerId!(playerId);
            },
      builder: (context, candidateData, rejectedData) {
        final sortedPlayers = [...players]
          ..sort((a, b) => b.ranking.compareTo(a.ranking));
        final isHighlighted = candidateData.isNotEmpty;

        return Card(
          shape: isHighlighted
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                )
              : null,
          child: Padding(
            padding: EdgeInsets.all(compact ? 10 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Drużyna ${teamIndex + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('Gracze: ${players.length}'),
                Text(
                  'Suma rankingu: ${NumberFormat.decimalPattern('pl').format(effectiveTeamRanking(totalRanking: _teamTotalRanking(players), teamSize: players.length, opponentTeamSize: opponentSize, playWithSubstitute: playWithSubstitute))}',
                ),
                const Divider(height: 18),
                if (sortedPlayers.isEmpty)
                  Container(
                    height: compact ? 52 : 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Przeciągnij tu graczy'),
                  )
                else
                  ...sortedPlayers.map(
                    (player) => DraftDraggablePlayerTile(
                      player: player,
                      trailing: onAcceptPlayerId == null
                          ? const SizedBox.shrink()
                          : const Icon(Icons.drag_indicator),
                      compact: compact,
                      dragData: onAcceptPlayerId == null
                          ? null
                          : player.playerId,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Map<String, Map<String, double>> _buildWinRateMatrix(
  List<HeadToHeadWinRate> winRates,
) {
  final matrix = <String, Map<String, double>>{};
  for (final rate in winRates) {
    final opponents = matrix.putIfAbsent(
      rate.playerId,
      () => <String, double>{},
    );
    opponents[rate.oppPlayerId] = rate.winRate;
  }
  return matrix;
}

List<List<Player>> _teamsFromDraft(Draft draft) {
  return [
    for (final team in draft.teams) [...team.players],
  ];
}

List<List<Player>> _cloneTeams(List<List<Player>> teams) {
  return [
    for (final team in teams) [...team],
  ];
}

List<List<String>> _teamPlayerIds(List<List<Player>> teams) {
  return [
    for (final team in teams)
      team.map((player) => player.playerId).toList(growable: false),
  ];
}

List<List<String>> _teamPlayerIdsFromDraft(Draft draft) {
  return [
    for (final team in draft.teams)
      team.players.map((player) => player.playerId).toList(growable: false),
  ];
}

bool _sameTeamAssignments(List<List<String>> left, List<List<String>> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    final leftTeam = left[index].toSet();
    final rightTeam = right[index].toSet();
    if (leftTeam.length != rightTeam.length ||
        !leftTeam.containsAll(rightTeam)) {
      return false;
    }
  }

  return true;
}

String? _extractPlayerId(Object data) {
  if (data is String && data.isNotEmpty) {
    return data;
  }
  return null;
}

double _teamTotalRanking(List<Player> players) {
  var total = 0.0;
  for (final player in players) {
    total += player.ranking;
  }
  return total;
}
