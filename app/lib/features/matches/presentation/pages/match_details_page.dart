import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:app/core/app_router.dart';
import 'package:app/core/utils/team_ranking.dart';
import 'package:app/features/matches/application/dto/match_details_dto.dart';
import 'package:app/features/matches/application/dto/player_dto.dart';
import 'package:app/features/matches/presentation/controllers/match_details_notifier.dart';
import 'package:app/features/matches/presentation/widgets/match_player_tile.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:app/features/matches/presentation/controllers/squad_matches_notifier.dart';
import 'package:app/core/app_config.dart';
import 'package:app/core/widgets/probability_slider.dart';

enum _MatchDetailsEditMode { none, teams, score }

class _MatchAction {
  const _MatchAction(this.label, this.onSelected);

  final String label;
  final VoidCallback onSelected;
}

class MatchDetailsPage extends ConsumerStatefulWidget {
  final String squadId;
  final String matchId;

  const MatchDetailsPage({
    super.key,
    required this.squadId,
    required this.matchId,
  });

  @override
  ConsumerState<MatchDetailsPage> createState() => _MatchDetailsPageState();
}

class _MatchDetailsPageState extends ConsumerState<MatchDetailsPage> {
  _MatchDetailsEditMode _editMode = _MatchDetailsEditMode.none;
  final TextEditingController _homeScoreController = TextEditingController();
  final TextEditingController _awayScoreController = TextEditingController();
  final TextEditingController _homeTeamNameController = TextEditingController();
  final TextEditingController _awayTeamNameController = TextEditingController();

  List<PlayerDto> _homePlayers = [];
  List<PlayerDto> _awayPlayers = [];
  bool _isDraggingPlayer = false;
  String? _homeTeamColorHex;
  String? _awayTeamColorHex;
  String? _initialHomeTeamName;
  String? _initialAwayTeamName;
  String? _initialHomeTeamColorHex;
  String? _initialAwayTeamColorHex;

  bool get _isEditing => _editMode != _MatchDetailsEditMode.none;
  bool get _isTeamEditing => _editMode == _MatchDetailsEditMode.teams;
  bool get _isScoreEditing => _editMode == _MatchDetailsEditMode.score;

  static const List<String> _teamColorOptions = [
    '#E53935',
    '#D81B60',
    '#8E24AA',
    '#5E35B1',
    '#3949AB',
    '#1E88E5',
    '#039BE5',
    '#00897B',
    '#43A047',
    '#7CB342',
    '#FDD835',
    '#FB8C00',
    '#6D4C41',
    '#546E7A',
  ];

  @override
  void dispose() {
    _homeScoreController.dispose();
    _awayScoreController.dispose();
    _homeTeamNameController.dispose();
    _awayTeamNameController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MatchDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matchId != widget.matchId) {
      _editMode = _MatchDetailsEditMode.none;
      _homePlayers = [];
      _awayPlayers = [];
      _isDraggingPlayer = false;
      _homeTeamNameController.clear();
      _awayTeamNameController.clear();
      _homeScoreController.clear();
      _awayScoreController.clear();
      _homeTeamColorHex = null;
      _awayTeamColorHex = null;
      _initialHomeTeamName = null;
      _initialAwayTeamName = null;
      _initialHomeTeamColorHex = null;
      _initialAwayTeamColorHex = null;
      ref.invalidate(matchDetailsProvider(widget.matchId));
    }
  }

  void _enterTeamEditMode(MatchDetailsDto match) {
    if (match.homeTeam == null || match.awayTeam == null) return;
    setState(() {
      _editMode = _MatchDetailsEditMode.teams;
      _homePlayers = List.from(match.homeTeam!.players);
      _awayPlayers = List.from(match.awayTeam!.players);
      _homeTeamNameController.text = match.homeTeam?.name ?? '';
      _awayTeamNameController.text = match.awayTeam?.name ?? '';
      _homeTeamColorHex = match.homeTeam?.color;
      _awayTeamColorHex = match.awayTeam?.color;
      _initialHomeTeamName = match.homeTeam?.name ?? '';
      _initialAwayTeamName = match.awayTeam?.name ?? '';
      _initialHomeTeamColorHex = match.homeTeam?.color;
      _initialAwayTeamColorHex = match.awayTeam?.color;
    });
  }

  void _enterScoreEditMode(MatchDetailsDto match) {
    setState(() {
      _editMode = _MatchDetailsEditMode.score;
      _homeScoreController.text = match.homeScore?.toString() ?? '';
      _awayScoreController.text = match.awayScore?.toString() ?? '';
    });
  }

  void _cancelEdit() {
    setState(() {
      _editMode = _MatchDetailsEditMode.none;
      _homePlayers.clear();
      _awayPlayers.clear();
      _isDraggingPlayer = false;
      _homeTeamNameController.clear();
      _awayTeamNameController.clear();
      _homeScoreController.clear();
      _awayScoreController.clear();
      _homeTeamColorHex = null;
      _awayTeamColorHex = null;
      _initialHomeTeamName = null;
      _initialAwayTeamName = null;
      _initialHomeTeamColorHex = null;
      _initialAwayTeamColorHex = null;
    });
  }

  Future<void> _saveChanges(MatchDetailsDto match) async {
    if (_isScoreEditing) {
      await _saveScoreChanges();
      return;
    }
    await _saveTeamChanges(match);
  }

  Future<void> _saveTeamChanges(MatchDetailsDto match) async {
    final homeTeam = match.homeTeam;
    final awayTeam = match.awayTeam;
    if (homeTeam == null || awayTeam == null) return;

    final nextHomeName = _homeTeamNameController.text.trim();
    final nextAwayName = _awayTeamNameController.text.trim();

    final homeNameChanged = nextHomeName != (_initialHomeTeamName ?? '');
    final awayNameChanged = nextAwayName != (_initialAwayTeamName ?? '');

    final homeColorChanged = _homeTeamColorHex != _initialHomeTeamColorHex;
    final awayColorChanged = _awayTeamColorHex != _initialAwayTeamColorHex;

    if (homeNameChanged ||
        awayNameChanged ||
        homeColorChanged ||
        awayColorChanged) {
      await ref
          .read(matchDetailsProvider(widget.matchId).notifier)
          .updateTeamsMeta(
            homeTeamId: homeTeam.teamId,
            awayTeamId: awayTeam.teamId,
            homeName: homeNameChanged ? nextHomeName : null,
            awayName: awayNameChanged ? nextAwayName : null,
            homeColor: homeColorChanged ? _homeTeamColorHex : null,
            awayColor: awayColorChanged ? _awayTeamColorHex : null,
          );
    }

    // 1. Save Teams FIRST
    final homeIds = _homePlayers.map((p) => p.playerId).toList();
    final awayIds = _awayPlayers.map((p) => p.playerId).toList();

    final homePlayersChanged = !_arePlayerIdsEqual(
      _homePlayers,
      homeTeam.players,
    );
    final awayPlayersChanged = !_arePlayerIdsEqual(
      _awayPlayers,
      awayTeam.players,
    );

    if (homePlayersChanged || awayPlayersChanged) {
      await ref
          .read(matchDetailsProvider(widget.matchId).notifier)
          .updateTeams(homeIds, awayIds);
    }

    if (mounted) {
      setState(() {
        _editMode = _MatchDetailsEditMode.none;
      });
    }

    // Ensure matches list refreshes when user goes back.
    ref.invalidate(squadMatchesProvider(widget.squadId));
  }

  Future<void> _saveScoreChanges() async {
    final homeScoreText = _homeScoreController.text.trim();
    final awayScoreText = _awayScoreController.text.trim();

    if (homeScoreText.isEmpty || awayScoreText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Podaj oba wyniki')));
      }
      return;
    }

    final home = int.tryParse(homeScoreText);
    final away = int.tryParse(awayScoreText);

    if (home == null || away == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Podaj poprawne wyniki')));
      }
      return;
    }
    await ref
        .read(matchDetailsProvider(widget.matchId).notifier)
        .updateScore(widget.squadId, home, away);

    if (mounted) {
      setState(() {
        _editMode = _MatchDetailsEditMode.none;
      });
    }

    // Ensure matches list refreshes when user goes back.
    ref.invalidate(squadMatchesProvider(widget.squadId));
  }

  Future<void> _deleteMatch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć mecz?'),
        content: const Text(
          'To cofnie wszystkie zmiany rankingu powiązane z tym meczem. Tej operacji nie można cofnąć.',
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

    await ref.read(matchDetailsProvider(widget.matchId).notifier).deleteMatch();

    if (mounted) {
      ref.invalidate(squadMatchesProvider(widget.squadId));
      context.goNamed(
        AppRoute.matches.name,
        pathParameters: {'squadId': widget.squadId},
      );
    }
  }

  Future<void> _onRematch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Utworzyć rewanż?'),
        content: const Text('Czy chcesz utworzyć rewanż?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Utwórz rewanż'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final newMatch = await ref
        .read(matchDetailsProvider(widget.matchId).notifier)
        .rematch();
    if (mounted) {
      context.pushNamed(
        AppRoute.matchDetails.name,
        pathParameters: {
          'squadId': widget.squadId,
          'matchId': newMatch.matchId,
        },
      );
    }
  }

  Future<void> _onRedraft(MatchDetailsDto match) async {
    if (match.homeTeam == null || match.awayTeam == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wylosować składy ponownie?'),
        content: const Text('Czy chcesz jeszcze raz wylosować składy?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wylosuj'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    final allPlayers = [...match.homeTeam!.players, ...match.awayTeam!.players];
    final selectedIds = allPlayers.map((p) => p.playerId).toList();

    context.pushNamed(
      AppRoute.draftCreate.name,
      pathParameters: {'squadId': widget.squadId},
      extra: {'selectedIds': selectedIds, 'matchId': widget.matchId},
    );
  }

  void _onPlayerDropped(Object? data, String targetSide) {
    if (data is! String) return;
    final playerId = data;

    // Find player in current lists
    final fromHome = _homePlayers.where((p) => p.playerId == playerId);
    final fromAway = _awayPlayers.where((p) => p.playerId == playerId);
    if (fromHome.isEmpty && fromAway.isEmpty) return;
    final player = fromHome.isNotEmpty ? fromHome.first : fromAway.first;

    setState(() {
      _homePlayers.removeWhere((p) => p.playerId == playerId);
      _awayPlayers.removeWhere((p) => p.playerId == playerId);

      if (targetSide == 'home') {
        _homePlayers.add(player);
      } else {
        _awayPlayers.add(player);
      }
    });
  }

  void _removePlayerFromMatch(Object? data) {
    if (data is! String) return;
    final playerId = data;
    setState(() {
      _homePlayers.removeWhere((p) => p.playerId == playerId);
      _awayPlayers.removeWhere((p) => p.playerId == playerId);
      _isDraggingPlayer = false;
    });
  }

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return Colors.grey;
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('0xFF$hex'));
    } catch (_) {
      return Colors.grey;
    }
  }

  String _displayTeamName(String? name, String fallback) {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  bool _arePlayerIdsEqual(List<PlayerDto> a, List<PlayerDto> b) {
    if (a.length != b.length) return false;
    final aIds = {for (final p in a) p.playerId};
    final bIds = {for (final p in b) p.playerId};
    return aIds.length == bIds.length && aIds.containsAll(bIds);
  }

  Future<void> _pickTeamColor(String side) async {
    final current = side == 'home' ? _homeTeamColorHex : _awayTeamColorHex;
    final theme = Theme.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wybierz kolor drużyny'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _teamColorOptions.map((hex) {
            final isSelected = hex == current;
            return InkWell(
              onTap: () => Navigator.of(context).pop(hex),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _parseColor(hex),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : Colors.grey.withValues(alpha: 0.5),
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Anuluj'),
          ),
        ],
      ),
    );

    if (!mounted || selected == null) return;
    setState(() {
      if (side == 'home') {
        _homeTeamColorHex = selected;
      } else {
        _awayTeamColorHex = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final matchAsync = ref.watch(matchDetailsProvider(widget.matchId));
    final squadAsync = ref.watch(squadDetailProvider(widget.squadId));

    final canManage =
        squadAsync.asData?.value.role == SquadRole.owner ||
        squadAsync.asData?.value.role == SquadRole.admin;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Score placement and team layout share the padded content width.
        final contentWidth = constraints.maxWidth.clamp(0.0, 1000.0) - 16;
        final compact = contentWidth < AppConfig.compactWidth;
        return Scaffold(
          appBar: AppBar(
            leading: Navigator.of(context).canPop()
                ? null
                : IconButton(
                    tooltip: 'Wróć do meczów',
                    onPressed: () {
                      context.goNamed(
                        AppRoute.matches.name,
                        pathParameters: {'squadId': widget.squadId},
                      );
                    },
                    icon: const Icon(Icons.arrow_back),
                  ),
            title: const Text('Szczegóły meczu'),
            titleTextStyle: Theme.of(context).textTheme.titleMedium,
            toolbarHeight: 48,
            actions: [
              if (canManage && matchAsync.hasValue) ...[
                if (_isEditing) ...[
                  IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: () => _saveChanges(matchAsync.value!),
                    tooltip: 'Zapisz',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _cancelEdit,
                    tooltip: 'Anuluj',
                  ),
                ] else ...[
                  PopupMenuButton<_MatchAction>(
                    tooltip: 'Akcje meczu',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) => action.onSelected(),
                    itemBuilder: (context) => [
                      for (final action in [
                        _MatchAction(
                          'Edytuj składy',
                          () => _enterTeamEditMode(matchAsync.value!),
                        ),
                        ..._matchActions(matchAsync.value!),
                        _MatchAction('Usuń mecz', _deleteMatch),
                      ])
                        PopupMenuItem(value: action, child: Text(action.label)),
                    ],
                  ),
                ],
              ],
            ],
          ),
          body: matchAsync.when(
            data: (match) => Stack(
              children: [
                _buildContent(context, match, compact: compact),
                if (_isTeamEditing && _isDraggingPlayer)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: _RemoveDropZone(onRemove: _removePlayerFromMatch),
                    ),
                  ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: SelectableText.rich(
                TextSpan(
                  text: 'Błąd: $error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<_MatchAction> _matchActions(MatchDetailsDto match) {
    final hasScore = match.homeScore != null && match.awayScore != null;
    final hasTeamAssignments =
        (match.homeTeam?.players.isNotEmpty ?? false) &&
        (match.awayTeam?.players.isNotEmpty ?? false);
    final hasTeamsPlayers =
        (match.homeTeam?.players.isNotEmpty ?? false) ||
        (match.awayTeam?.players.isNotEmpty ?? false);
    final isTournamentMatch = match.tournamentId != null;
    return [
      if (hasTeamsPlayers)
        _MatchAction('Wprowadź wynik', () => _enterScoreEditMode(match)),
      _MatchAction('Podgląd propozycji', () {
        context.pushNamed(
          AppRoute.matchDraft.name,
          pathParameters: {
            'squadId': widget.squadId,
            'matchId': widget.matchId,
          },
        );
      }),
      if (!isTournamentMatch && !hasScore && hasTeamAssignments)
        _MatchAction('Wylosuj jeszcze raz', () => _onRedraft(match)),
      if (!hasTeamAssignments && hasTeamsPlayers)
        _MatchAction('Zmień drużyny', () {
          final selectedIds = <String>{
            for (final player in match.homeTeam?.players ?? const [])
              player.playerId,
            for (final player in match.awayTeam?.players ?? const [])
              player.playerId,
          }.toList(growable: false);
          context.pushNamed(
            AppRoute.draftCreate.name,
            pathParameters: {'squadId': widget.squadId},
            extra: {'selectedIds': selectedIds, 'matchId': widget.matchId},
          );
        }),
      if (!isTournamentMatch && hasTeamsPlayers)
        _MatchAction('Rewanż', _onRematch),
    ];
  }

  Widget _buildContent(
    BuildContext context,
    MatchDetailsDto match, {
    required bool compact,
  }) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    final bottomInset = _isTeamEditing && _isDraggingPlayer ? 84.0 : 0.0;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(8, 4, 8, 8 + bottomInset),
          child: Column(
            children: [
              Text(
                dateFormat.format(match.createdAt.toLocal()),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (compact)
                _isScoreEditing
                    ? _buildEditScoreBoard(compact: true)
                    : _buildScoreBoard(match, compact: true),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final scoreBoard = _isScoreEditing
                      ? _buildEditScoreBoard(compact: compact)
                      : _buildScoreBoard(match, compact: compact);
                  final homeSection = _buildTeamSection(
                    context,
                    _isTeamEditing
                        ? _homePlayers
                        : (match.homeTeam?.players ?? const <PlayerDto>[]),
                    match.homeTeam?.name,
                    'Gospodarze',
                    'home',
                    _isTeamEditing ? _homeTeamColorHex : match.homeTeam?.color,
                    opponentCount: _isTeamEditing
                        ? _awayPlayers.length
                        : (match.awayTeam?.players.length ?? 0),
                    nameController: _isTeamEditing
                        ? _homeTeamNameController
                        : null,
                    compact: compact,
                  );
                  final awaySection = _buildTeamSection(
                    context,
                    _isTeamEditing
                        ? _awayPlayers
                        : (match.awayTeam?.players ?? const <PlayerDto>[]),
                    match.awayTeam?.name,
                    'Goście',
                    'away',
                    _isTeamEditing ? _awayTeamColorHex : match.awayTeam?.color,
                    opponentCount: _isTeamEditing
                        ? _homePlayers.length
                        : (match.homeTeam?.players.length ?? 0),
                    nameController: _isTeamEditing
                        ? _awayTeamNameController
                        : null,
                    compact: compact,
                  );

                  final gap = compact ? 8.0 : 16.0;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: homeSection),
                      SizedBox(width: gap),
                      if (!compact) ...[
                        SizedBox(
                          width: 220,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: scoreBoard,
                          ),
                        ),
                        SizedBox(width: gap),
                      ],
                      Expanded(child: awaySection),
                    ],
                  );
                },
              ),

              if (_isTeamEditing) ...[
                const SizedBox(height: 12),
                Text(
                  'Przeciągnij by zmienić drużyny.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (!_isEditing && match.homeWinProbability != null) ...[
                const SizedBox(height: 24),
                ProbabilitySlider(
                  title: 'Szansa na wygraną',
                  homeColor: _parseColor(match.homeTeam?.color),
                  awayColor: _parseColor(match.awayTeam?.color),
                  homeProbability: match.homeWinProbability!,
                  infoText:
                      'Szacowane na podstawie historycznych wyników bezpośrednich pojedynków między '
                      'graczami w tym składzie.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreBoard(MatchDetailsDto match, {required bool compact}) {
    final hasScore = match.homeScore != null && match.awayScore != null;
    final homeScore = hasScore ? match.homeScore.toString() : '-';
    final awayScore = hasScore ? match.awayScore.toString() : '-';
    final fontSize = compact ? 24.0 : 48.0;
    final separatorSize = compact ? 24.0 : 48.0;
    final padding = compact ? 8.0 : 16.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          homeScore,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Text(':', style: TextStyle(fontSize: separatorSize)),
        ),
        Text(
          awayScore,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildEditScoreBoard({required bool compact}) {
    final fontSize = compact ? 24.0 : 32.0;
    final width = compact ? MediaQuery.textScalerOf(context).scale(80) : 80.0;
    final padding = compact ? 8.0 : 16.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: SizedBox(
            width: width,
            child: TextField(
              controller: _homeScoreController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Gospodarze',
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Text(':', style: TextStyle(fontSize: fontSize + 8)),
        ),
        Flexible(
          child: SizedBox(
            width: width,
            child: TextField(
              controller: _awayScoreController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Goście',
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _effectiveTeamRating(List<PlayerDto> players, int opponentCount) {
    double totalRanking = 0;
    for (final p in players) {
      totalRanking += p.ranking;
    }
    final playWithSubstitute = players.length != opponentCount;
    return effectiveTeamRanking(
      totalRanking: totalRanking,
      teamSize: players.length,
      opponentTeamSize: opponentCount,
      playWithSubstitute: playWithSubstitute,
    );
  }

  Widget _buildTeamColorBox({
    required BuildContext context,
    required Color color,
    required double size,
    required bool editable,
  }) {
    final theme = Theme.of(context);
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: editable
              ? theme.colorScheme.primary
              : Colors.grey.withValues(alpha: 0.5),
          width: editable ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: editable
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.28),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );

    if (!editable) {
      return box;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.primary, width: 1),
            ),
            child: Icon(
              Icons.edit,
              size: 8,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditableTeamNameField({
    required BuildContext context,
    required TextEditingController controller,
    required String hintText,
    required TextAlign textAlign,
    TextStyle? style,
    double? maxWidth,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      child: TextField(
        controller: controller,
        textAlign: textAlign,
        style: style,
        decoration: InputDecoration(
          hintText: hintText,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Colors.green, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Colors.green, width: 2.4),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamSection(
    BuildContext context,
    List<PlayerDto> players,
    String? teamName,
    String fallbackLabel,
    String side,
    String? colorHex, {
    required int opponentCount,
    TextEditingController? nameController,
    required bool compact,
    bool showHeader = true,
  }) {
    final teamColor = _parseColor(colorHex);
    final theme = Theme.of(context);
    final sortedPlayers = [...players]
      ..sort((a, b) => b.ranking.compareTo(a.ranking));

    final effective = _effectiveTeamRating(players, opponentCount);

    final list = Column(
      children: [
        if (showHeader) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _isTeamEditing
                  ? GestureDetector(
                      onTap: () => _pickTeamColor(side),
                      child: Tooltip(
                        message: 'Zmień kolor',
                        child: _buildTeamColorBox(
                          context: context,
                          color: teamColor,
                          size: compact ? 14 : 32,
                          editable: true,
                        ),
                      ),
                    )
                  : _buildTeamColorBox(
                      context: context,
                      color: teamColor,
                      size: compact ? 14 : 32,
                      editable: false,
                    ),
              SizedBox(width: compact ? 6 : 8),
              if (_isTeamEditing && nameController != null)
                Flexible(
                  child: _buildEditableTeamNameField(
                    context: context,
                    controller: nameController,
                    hintText: fallbackLabel,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: compact ? 16 : null,
                    ),
                    maxWidth: compact ? 140 : 200,
                  ),
                )
              else
                Flexible(
                  child: Text(
                    _displayTeamName(teamName, fallbackLabel),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: compact ? 14 : null,
                    ),
                  ),
                ),
              // Balance the color marker so the name itself stays centered.
              SizedBox(width: compact ? 20 : 40),
            ],
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            'Ranking: ${effective.toStringAsFixed(1)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: compact ? 11 : null,
            ),
          ),
          const Divider(height: 6),
        ],
        ...sortedPlayers.map(
          (player) => MatchPlayerTile(
            player: player,
            trailing: null,
            dragData: _isTeamEditing ? player.playerId : null,
            compact: compact,
            onDragStarted: _isTeamEditing
                ? () => setState(() => _isDraggingPlayer = true)
                : null,
            onDragEnd: _isTeamEditing
                ? () => setState(() => _isDraggingPlayer = false)
                : null,
            onTap: !_isTeamEditing
                ? () {
                    context.pushNamed(
                      AppRoute.playerDetails.name,
                      pathParameters: {
                        'squadId': widget.squadId,
                        'playerId': player.playerId,
                      },
                    );
                  }
                : null,
          ),
        ),
        if (_isTeamEditing && players.isEmpty)
          Container(
            height: compact ? 48 : 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Przeciągnij graczy tutaj'),
          ),
      ],
    );

    if (_isTeamEditing) {
      return DragTarget<Object>(
        builder: (context, candidateData, rejectedData) {
          return Container(
            decoration: BoxDecoration(
              color: candidateData.isNotEmpty
                  ? theme.colorScheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: list,
          );
        },
        onAcceptWithDetails: (details) => _onPlayerDropped(details.data, side),
      );
    }

    return list;
  }
}

class _RemoveDropZone extends StatelessWidget {
  const _RemoveDropZone({required this.onRemove});

  final ValueChanged<Object?> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => details.data is String,
      onAcceptWithDetails: (details) => onRemove(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;
        return Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: theme.colorScheme.error.withValues(
            alpha: isHighlighted ? 0.25 : 0.18,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close, color: theme.colorScheme.error, size: 28),
              const SizedBox(width: 8),
              Text(
                'Przeciągnij tutaj, aby usunąć',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
