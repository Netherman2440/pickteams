import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:app/core/app_config.dart';
import 'package:app/core/app_router.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/core/utils/team_ranking.dart';
import 'package:app/core/widgets/probability_slider.dart';
import 'package:app/core/widgets/lineup_header.dart';
import 'package:app/core/widgets/team_transfer_target.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/domain/services/draft_algorithm_policy.dart';
import 'package:app/features/draft/application/get_match_draft_use_case.dart';
import 'package:app/features/draft/application/accept_match_draft_use_case.dart';
import 'package:app/features/draft/infrastructure/repositories/supabase_draft_acceptance_repository.dart';
import 'package:app/features/draft/presentation/controllers/draft_session_notifier.dart';
import 'package:app/features/draft/presentation/widgets/draft_draggable_player_tile.dart';
import 'package:app/features/draft/presentation/widgets/draft_relation_widgets.dart';
import 'package:app/features/matches/application/usecases/get_match_usecase.dart';
import 'package:app/features/matches/presentation/controllers/match_details_notifier.dart';
import 'package:app/features/matches/presentation/controllers/squad_matches_notifier.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/players_providers.dart';

final _logger = Logger('DraftResultsPage');

class DraftResultsPage extends ConsumerStatefulWidget {
  const DraftResultsPage({
    super.key,
    required this.squadId,
    required this.selectedPlayerIds,
    this.draftRules = const [],
    this.matchId,
    this.playWithSubstitute = true,
  });

  final String squadId;
  final List<String> selectedPlayerIds;
  final List<DraftRule> draftRules;
  final String? matchId;
  final bool playWithSubstitute;

  @override
  ConsumerState<DraftResultsPage> createState() => _DraftResultsPageState();
}

class _DraftResultsPageState extends ConsumerState<DraftResultsPage> {
  bool _playWithSubstitute = true;
  bool _accepting = false;
  bool _acceptanceStarted = false;
  late final DraftSessionNotifier _session;

  @override
  void dispose() {
    _session.cancelLoad();
    super.dispose();
  }

  void _back() {
    if (_accepting) return;
    if (widget.selectedPlayerIds.isEmpty && _loadMatchId != null) {
      context.goNamed(
        AppRoute.matchDetails.name,
        pathParameters: {'squadId': widget.squadId, 'matchId': _loadMatchId!},
      );
      return;
    }
    context.goNamed(
      AppRoute.draftSelection.name,
      pathParameters: {'squadId': widget.squadId},
      extra: {
        'selectedIds': widget.selectedPlayerIds,
        'draftRules': serializeDraftRules(widget.draftRules),
        'playWithSubstitute': _playWithSubstitute,
        'matchId': _loadMatchId,
      },
    );
  }

  int? _loadingPlayerCount;
  _DraftLoadingMode _loadingMode = _DraftLoadingMode.generating;

  String? get _loadMatchId {
    final value = widget.matchId;
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  void initState() {
    super.initState();
    _session = ref.read(draftSessionNotifierProvider.notifier);
    _playWithSubstitute = widget.playWithSubstitute;
    _loadingPlayerCount = widget.selectedPlayerIds.length;
    _loadingMode = widget.selectedPlayerIds.length >= 2
        ? _DraftLoadingMode.generating
        : _DraftLoadingMode.checkingExisting;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session.load(
        squadId: widget.squadId,
        selectedPlayerIds: widget.selectedPlayerIds,
        algorithm: _preferredAlgorithm,
        matchId: _loadMatchId,
        playWithSubstitute: _playWithSubstitute,
        rules: widget.draftRules,
      );
    });
    Future.microtask(_resolveLoadingModeAndCount);
  }

  @override
  void didUpdateWidget(covariant DraftResultsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playWithSubstitute != widget.playWithSubstitute) {
      _playWithSubstitute = widget.playWithSubstitute;
    }
    if (oldWidget.matchId != widget.matchId ||
        oldWidget.selectedPlayerIds != widget.selectedPlayerIds) {
      _loadingPlayerCount = widget.selectedPlayerIds.length;
      _loadingMode = widget.selectedPlayerIds.length >= 2
          ? _DraftLoadingMode.generating
          : _DraftLoadingMode.checkingExisting;
      Future.microtask(_resolveLoadingModeAndCount);
    }
  }

  Future<void> _resolveLoadingModeAndCount() async {
    final matchId = _loadMatchId;
    if (widget.selectedPlayerIds.length >= 2 || matchId == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMode = _DraftLoadingMode.generating;
      });
      return;
    }

    try {
      final storedDraft = await ref
          .read(getMatchDraftUseCaseProvider)
          .execute(matchId: matchId);
      if (!mounted) {
        return;
      }

      if (storedDraft != null) {
        setState(() {
          _loadingMode = _DraftLoadingMode.checkingExisting;
        });
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMode = _DraftLoadingMode.checkingExisting;
      });
      return;
    }

    await _hydrateLoadingPlayerCount();
  }

  DraftAlgorithm get _preferredAlgorithm {
    final selectedCount = widget.selectedPlayerIds.toSet().length;
    return switch (DraftAlgorithmPolicy.resolve(
      teamCount: 2,
      playerCount: selectedCount,
    )) {
      DraftAlgorithmSelection.greedy => DraftAlgorithm.greedy,
      DraftAlgorithmSelection.combinatory => DraftAlgorithm.combinatory,
    };
  }

  Future<void> _hydrateLoadingPlayerCount() async {
    final matchId = _loadMatchId;
    if (matchId == null || widget.selectedPlayerIds.length >= 2) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMode = _DraftLoadingMode.generating;
      });
      return;
    }

    try {
      final rankingEntries = await ref
          .read(rankingRepositoryProvider)
          .getMatchRankingHistory(matchId);
      var count = rankingEntries.map((entry) => entry.playerId).toSet().length;

      if (count < 2) {
        final match = await ref
            .read(getMatchUseCaseProvider)
            .execute(matchId: matchId);
        count = <String>{
          for (final player in match.homeTeam?.players ?? const [])
            player.playerId,
          for (final player in match.awayTeam?.players ?? const [])
            player.playerId,
        }.length;
      }

      if (!mounted) {
        return;
      }

      if (count > 0) {
        setState(() {
          _loadingPlayerCount = count;
          _loadingMode = count >= 2
              ? _DraftLoadingMode.generating
              : _DraftLoadingMode.checkingExisting;
        });
      }
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to hydrate loading player count for matchId=$matchId',
        error,
        stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(draftSessionNotifierProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: ScaffoldMessenger(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Wstecz',
              onPressed: _accepting ? null : _back,
              icon: const Icon(Icons.arrow_back),
            ),
            title: const Text('Propozycja'),
            toolbarHeight: 48,
            titleTextStyle: Theme.of(context).textTheme.titleMedium,
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _CreateMatchButton(
                squadId: widget.squadId,
                matchId: widget.matchId,
                onSubmitting: (pending) => setState(() {
                  _accepting = pending;
                  _acceptanceStarted = true;
                }),
              ),
            ),
          ),
          body: state.when(
            loading: () => _DraftLoadingBody(
              selectedPlayerCount:
                  _loadingPlayerCount ?? widget.selectedPlayerIds.length,
              showCombinationCount:
                  _loadingMode == _DraftLoadingMode.generating,
            ),
            error: (error, _) => _ErrorBody(
              error: error,
              squadId: widget.squadId,
              matchId: _loadMatchId,
              selectedPlayerIds: widget.selectedPlayerIds,
              playWithSubstitute: _playWithSubstitute,
              draftRules: widget.draftRules,
            ),
            data: (data) {
              if (data.proposals.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Brak propozycji. Wróć i wybierz graczy.'),
                );
              }

              return AbsorbPointer(
                absorbing: _acceptanceStarted,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _ProposalNavigator(
                            index: data.selectedIndex,
                            total: data.proposals.length,
                            onPrev: data.selectedIndex == 0
                                ? null
                                : () => ref
                                      .read(
                                        draftSessionNotifierProvider.notifier,
                                      )
                                      .selectProposal(data.selectedIndex - 1),
                            onNext:
                                data.selectedIndex == data.proposals.length - 1
                                ? null
                                : () => ref
                                      .read(
                                        draftSessionNotifierProvider.notifier,
                                      )
                                      .selectProposal(data.selectedIndex + 1),
                          ),
                        ),
                        LineupHeader(
                          homeName: 'Gospodarze',
                          awayName: 'Goście',
                          homeColor: _teamColor(data.homeColor),
                          awayColor: _teamColor(data.awayColor),
                          stackedIdentity: true,
                          homeRanking:
                              'Ranking: ${_uiTeamScore(players: data.home, opponentCount: data.away.length, playWithSubstitute: data.proposals[data.selectedIndex].playWithSubstitute).toStringAsFixed(1)}',
                          awayRanking:
                              'Ranking: ${_uiTeamScore(players: data.away, opponentCount: data.home.length, playWithSubstitute: data.proposals[data.selectedIndex].playWithSubstitute).toStringAsFixed(1)}',
                        ),
                        LineupBody(
                          collapseExtent: 96,
                          child: Column(
                            children: [
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final home in [true, false]) ...[
                                      if (!home) const SizedBox(width: 12),
                                      Expanded(
                                        child: _RosterPanel(
                                          players: home ? data.home : data.away,
                                          compact: true,
                                          onAcceptPlayerId: (id) => ref
                                              .read(
                                                draftSessionNotifierProvider
                                                    .notifier,
                                              )
                                              .movePlayer(
                                                playerId: id,
                                                toHome: home,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'Przytrzymaj gracza i przeciągnij do drugiej drużyny.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              ProbabilitySlider(
                                title: 'Szansa wygranej propozycji',
                                homeProbability: data.homeWinProbability,
                                infoText:
                                    'Obliczono na podstawie współczynników wygranych bezpośrednich '
                                    'pojedynków między wybranymi graczami.',
                                homeColor: _teamColor(data.homeColor),
                                awayColor: _teamColor(data.awayColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DraftLoadingBody extends StatelessWidget {
  const _DraftLoadingBody({
    required this.selectedPlayerCount,
    required this.showCombinationCount,
  });

  final int selectedPlayerCount;
  final bool showCombinationCount;

  @override
  Widget build(BuildContext context) {
    final usesGreedyHeuristic =
        selectedPlayerCount >= AppConfig.greedyDraftThresholdPlayers;
    final count = usesGreedyHeuristic
        ? BigInt.from(AppConfig.greedyDraftVariantChecks)
        : _estimatedCheckedDraftCount(
            playerCount: selectedPlayerCount,
            teamCount: 2,
          );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          const Text('Trwa generowanie propozycji. To może chwilę potrwać.'),
          const SizedBox(height: 8),
          Text(
            showCombinationCount
                ? (count == null
                      ? 'Sprawdzane warianty: wyliczanie...'
                      : 'Sprawdzane warianty: ${_formatBigInt(count)}')
                : 'Sprawdzam zapisaną propozycję...',
          ),
          if (showCombinationCount) ...[
            const SizedBox(height: 6),
            const Text(
              'Możesz wyjść z tego ekranu, ale nie zamykaj przeglądarki.',
            ),
            if (usesGreedyHeuristic) ...[
              const SizedBox(height: 6),
              const Text(
                'Uwaga: przy większej liczbie graczy wynik propozycji '
                'może być mniej dokładny.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

enum _DraftLoadingMode { checkingExisting, generating }

class _CreateMatchButton extends ConsumerStatefulWidget {
  const _CreateMatchButton({
    required this.squadId,
    this.matchId,
    required this.onSubmitting,
  });
  final String squadId;
  final String? matchId;
  final ValueChanged<bool> onSubmitting;
  @override
  ConsumerState<_CreateMatchButton> createState() => _CreateMatchButtonState();
}

class _CreateMatchButtonState extends ConsumerState<_CreateMatchButton> {
  late final _accept = AcceptMatchDraftUseCase(
    ref.read(draftAcceptanceRepositoryProvider),
  );
  bool _pending = false;

  @override
  Widget build(BuildContext context) {
    final draftState = ref.watch(draftSessionNotifierProvider);
    final draftData = draftState.asData?.value;

    final matchId = widget.matchId;
    final squadId = widget.squadId;
    final isExistingMatch = matchId != null && matchId.isNotEmpty;
    final hasProposals = draftData != null && draftData.proposals.isNotEmpty;

    final isLoading = _pending;

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.green),
        foregroundColor: Colors.green,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: isLoading || !hasProposals
          ? null
          : () async {
              if (_pending) return;
              setState(() => _pending = true);
              widget.onSubmitting(true);
              try {
                final acceptedId = await _accept.execute(
                  squadId: squadId,
                  matchId: matchId,
                  homePlayerIds: draftData.home.map((p) => p.playerId).toList(),
                  awayPlayerIds: draftData.away.map((p) => p.playerId).toList(),
                  proposals: draftData.proposals,
                  selectedIndex: draftData.selectedIndex,
                  winRateMatrix: draftData.winRateMatrix,
                  seed: draftData.seed,
                );
                if (!context.mounted) return;
                if (isExistingMatch) {
                  ref.invalidate(matchDetailsProvider(matchId));
                }
                ref.invalidate(squadMatchesProvider(squadId));
                context.goNamed(
                  AppRoute.matchDetails.name,
                  pathParameters: {'squadId': squadId, 'matchId': acceptedId},
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                      'Nie udało się zapisać propozycji. Ponów akceptację tej propozycji: $error',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              } finally {
                if (mounted) {
                  setState(() => _pending = false);
                  widget.onSubmitting(false);
                }
              }
            },
      child: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Zakceptuj propozycję'),
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
        Flexible(
          child: Text(
            'Propozycja ${index + 1} z $total',
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

double _uiTeamScore({
  required List<Player> players,
  required int opponentCount,
  required bool playWithSubstitute,
}) {
  var total = 0.0;
  for (final player in players) {
    total += player.ranking;
  }

  return effectiveTeamRanking(
    totalRanking: total,
    teamSize: players.length,
    opponentTeamSize: opponentCount,
    playWithSubstitute: playWithSubstitute,
  );
}

class _RosterPanel extends StatelessWidget {
  const _RosterPanel({
    required this.players,
    required this.compact,
    required this.onAcceptPlayerId,
  });

  final List<Player> players;
  final bool compact;
  final ValueChanged<String> onAcceptPlayerId;

  @override
  Widget build(BuildContext context) {
    final sortedPlayers = [...players]
      ..sort((a, b) => b.ranking.compareTo(a.ranking));
    return TeamTransferTarget(
      playerIds: players.map((p) => p.playerId),
      onAccept: onAcceptPlayerId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (players.isEmpty) const Text('Brak graczy.'),
          for (final p in sortedPlayers)
            DraftDraggablePlayerTile(
              key: ValueKey(p.playerId),
              player: p,
              trailing: const SizedBox.shrink(),
              dragData: p.playerId,
              compact: compact,
              simple: true,
            ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.error,
    required this.squadId,
    required this.matchId,
    required this.selectedPlayerIds,
    required this.playWithSubstitute,
    required this.draftRules,
  });

  final Object error;
  final String squadId;
  final String? matchId;
  final List<String> selectedPlayerIds;
  final bool playWithSubstitute;
  final List<DraftRule> draftRules;

  @override
  Widget build(BuildContext context) {
    final err = error;
    final message = err is Failure ? err.message : err.toString();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText.rich(
            TextSpan(
              text: message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          if (matchId != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                context.pushNamed(
                  AppRoute.draftAgainstRelations.name,
                  pathParameters: {'squadId': squadId},
                  extra: {
                    'selectedIds': selectedPlayerIds,
                    'matchId': matchId,
                    'playWithSubstitute': playWithSubstitute,
                    'draftRules': serializeDraftRules(draftRules),
                  },
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Wybierz zawodników i spróbuj ponownie'),
            ),
          ],
        ],
      ),
    );
  }
}

BigInt? _estimatedCheckedDraftCount({
  required int playerCount,
  required int teamCount,
}) {
  if (playerCount < teamCount || playerCount <= 0 || teamCount <= 0) {
    return null;
  }

  final teamSizes = _calculateTeamSizes(
    playerCount: playerCount,
    teamCount: teamCount,
  );

  var remainingPlayers = playerCount;
  var count = BigInt.one;

  for (var i = 0; i < teamSizes.length - 1; i++) {
    final teamSize = teamSizes[i];
    count *= _binomial(remainingPlayers - 1, teamSize - 1);
    remainingPlayers -= teamSize;
  }

  return count;
}

List<int> _calculateTeamSizes({
  required int playerCount,
  required int teamCount,
}) {
  final base = playerCount ~/ teamCount;
  final remainder = playerCount % teamCount;

  return List<int>.generate(
    teamCount,
    (index) => base + (index < remainder ? 1 : 0),
  );
}

BigInt _binomial(int n, int k) {
  if (k < 0 || n < 0 || k > n) {
    return BigInt.zero;
  }

  var adjusted = k;
  if (adjusted > n - adjusted) {
    adjusted = n - adjusted;
  }

  var result = BigInt.one;
  for (var i = 1; i <= adjusted; i++) {
    result = (result * BigInt.from(n - adjusted + i)) ~/ BigInt.from(i);
  }

  return result;
}

String _formatBigInt(BigInt value) {
  final digits = value.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    final isSeparator = i > 0 && (digits.length - i) % 3 == 0;
    if (isSeparator) {
      buffer.write(' ');
    }
    buffer.write(digits[i]);
  }

  return buffer.toString();
}

Color _teamColor(String hex) => Color(
  int.tryParse('FF${hex.replaceFirst('#', '')}', radix: 16) ?? 0xFF808080,
);
