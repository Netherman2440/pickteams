// Credential-free harness for the real profile and its existing dialogs.
import 'package:app/core/app_theme.dart';
import 'package:app/core/root_shell.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/players/application/usecases/update_player_name_usecase.dart';
import 'package:app/features/players/application/usecases/update_player_position_usecase.dart';
import 'package:app/features/players/application/usecases/update_player_ranking_usecase.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/entities/ranking_history_entry.dart';
import 'package:app/features/players/presentation/controllers/player_details_controller.dart';
import 'package:app/features/players/presentation/pages/player_details_page.dart';
import 'package:app/features/squads/domain/entities/squad.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ProfileFixtureData {
  ProfileFixtureData({this.fail = false, bool longName = false})
    : player = Player(
        playerId: 'player',
        squadId: 'fixture',
        name: longName
            ? 'Aleksander Konstanty Wiśniewski-Kowalski'
            : 'Jan Testowy',
        ranking: 59.36,
        baseRanking: 54,
        createdAt: DateTime(2026),
      );
  Player player;
  bool fail;
  int reads = 0;
  final List<String> writes = [];
  void save(String field) {
    if (fail) throw Exception('Fixture save failed');
    writes.add(field);
  }
}

class PlayerDetailsFixture extends StatefulWidget {
  const PlayerDetailsFixture({
    super.key,
    required this.data,
    this.role = SquadRole.owner,
    this.textScale = 1,
  });
  final ProfileFixtureData data;
  final SquadRole role;
  final double textScale;
  @override
  State<PlayerDetailsFixture> createState() => _PlayerDetailsFixtureState();
}

class _PlayerDetailsFixtureState extends State<PlayerDetailsFixture> {
  late final router = GoRouter(
    initialLocation: '/squads/fixture/players/player',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            RootShell(location: state.uri.toString(), child: child),
        routes: [
          GoRoute(
            path: '/squads/:squadId/players/:playerId',
            name: 'playerDetails',
            builder: (_, _) =>
                const PlayerDetailsPage(squadId: 'fixture', playerId: 'player'),
          ),
          for (final destination in ['Matches', 'Tournaments', 'Stats'])
            GoRoute(
              path:
                  '/squads/:squadId/players/:playerId/${destination.toLowerCase()}',
              name: 'player$destination',
              builder: (_, state) => Scaffold(
                body: Text(
                  '$destination ${state.pathParameters['squadId']} ${state.pathParameters['playerId']}',
                ),
              ),
            ),
        ],
      ),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      authStateProvider.overrideWith(_ProfileAuth.new),
      squadDetailProvider.overrideWith(
        (ref, id) async => Squad(
          squadId: id,
          ownerId: 'fixture',
          name: 'Skład testowy',
          visibility: SquadVisibility.private,
          sportType: SportType.football,
          createdAt: DateTime(2026),
          role: widget.role,
        ),
      ),
      playerDetailsProvider.overrideWith((ref, id) async {
        widget.data.reads++;
        return PlayerDetailsState(
          player: widget.data.player,
          rankingHistory: [
            // Pre-event rankings and deltas: 54 → 57.12 → 61.234 → 59.36.
            // Both gains and losses must survive the real graph's delta filter.
            for (final (i, event) in [
              (54.0, 3.12),
              (57.12, 4.114),
              (61.234, -1.874),
            ].indexed)
              RankingHistoryEntry(
                rankingHistoryId: 'h$i',
                playerId: id,
                ranking: event.$1,
                change: event.$2,
                createdAt: DateTime(2026, 1, i + 1),
              ),
          ],
        );
      }),
      updatePlayerNameUseCaseProvider.overrideWithValue(
        _NameUpdate(widget.data),
      ),
      updatePlayerRankingUseCaseProvider.overrideWithValue(
        _RankingUpdate(widget.data),
      ),
      updatePlayerPositionUseCaseProvider.overrideWithValue(
        _PositionUpdate(widget.data),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
        child: child!,
      ),
    ),
  );
}

class _ProfileAuth extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() => AsyncData(
    AuthEntity(
      accessToken: '',
      refreshToken: '',
      userId: 'fixture',
      isAnonymous: false,
      email: 'fixture@example.invalid',
    ),
  );
}

class _NameUpdate implements UpdatePlayerNameUseCase {
  _NameUpdate(this.data);
  final ProfileFixtureData data;
  @override
  Future<void> execute({
    required String playerId,
    required String newName,
  }) async {
    data.save('name');
    data.player = data.player.copyWith(name: newName);
  }
}

class _RankingUpdate implements UpdatePlayerRankingUseCase {
  _RankingUpdate(this.data);
  final ProfileFixtureData data;
  @override
  Future<void> execute({
    required String playerId,
    required double newRanking,
  }) async {
    data.save('ranking');
    data.player = data.player.copyWith(ranking: newRanking);
  }
}

class _PositionUpdate implements UpdatePlayerPositionUseCase {
  _PositionUpdate(this.data);
  final ProfileFixtureData data;
  @override
  Future<void> execute({
    required String playerId,
    required String? newPosition,
  }) async {
    data.save('position');
    final p = data.player;
    data.player = Player(
      playerId: p.playerId,
      squadId: p.squadId,
      name: p.name,
      ranking: p.ranking,
      baseRanking: p.baseRanking,
      createdAt: p.createdAt,
      position: newPosition,
    );
  }
}
