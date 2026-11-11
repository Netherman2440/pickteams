// Real RootShell pages with synthetic players and no network dependencies.
import 'package:app/core/app_theme.dart';
import 'package:app/core/root_shell.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/draft/presentation/pages/draft_selection_page.dart';
import 'package:app/features/players/application/usecases/get_squad_players_usecase.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/repositories/player_repository.dart';
import 'package:app/features/players/presentation/widgets/players_list_widget.dart';
import 'package:app/features/squads/domain/entities/squad.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final sharedRowsPlayers = List.generate(
  100,
  (i) => Player(
    playerId: 'p${i + 1}',
    squadId: 'fixture',
    name: i == 0
        ? 'Aleksander Konstanty Wiśniewski-Kowalski'
        : i == 1
        ? 'Anna'
        : 'Gracz ${i + 1}',
    ranking: 60.25 - i / 2,
    baseRanking: 50,
    createdAt: DateTime(2026, 1, 1),
  ),
);

class SharedRowsFixture extends StatefulWidget {
  const SharedRowsFixture({
    super.key,
    this.players,
    this.initialSelectedIds = const ['p1', 'p2'],
    this.page = 'selection',
    this.textScale = 1,
    this.error,
  });
  final List<Player>? players;
  final List<String> initialSelectedIds;
  final String page;
  final double textScale;
  final Object? error;

  @override
  State<SharedRowsFixture> createState() => _SharedRowsFixtureState();
}

class _SharedRowsFixtureState extends State<SharedRowsFixture> {
  late final router = GoRouter(
    initialLocation: '/squads/fixture/${widget.page}',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            RootShell(location: state.uri.toString(), child: child),
        routes: [
          GoRoute(
            path: '/squads/:squadId/selection',
            builder: (_, _) => DraftSelectionPage(
              squadId: 'fixture',
              initialSelectedIds: widget.initialSelectedIds,
            ),
          ),
          GoRoute(
            path: '/squads/:squadId/players',
            builder: (_, _) => Scaffold(
              appBar: AppBar(title: const Text('Gracze')),
              body: PlayersListWidget(
                players: widget.players ?? sharedRowsPlayers,
                squadId: 'fixture',
              ),
            ),
          ),
          GoRoute(
            path: '/squads/:squadId/players/:playerId',
            name: 'playerDetails',
            builder: (_, state) => Scaffold(
              body: Text('Profile: ${state.pathParameters['playerId']}'),
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
      authStateProvider.overrideWith(_Auth.new),
      squadDetailProvider.overrideWith(
        (ref, id) async => Squad(
          squadId: id,
          ownerId: 'fixture',
          name: 'Przykładowy skład',
          visibility: SquadVisibility.private,
          sportType: SportType.football,
          createdAt: DateTime(2026, 1, 1),
          role: SquadRole.owner,
        ),
      ),
      getSquadPlayersUseCaseProvider.overrideWithValue(
        GetSquadPlayersUseCase(
          _Players(widget.players ?? sharedRowsPlayers, widget.error),
        ),
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

class _Auth extends AuthNotifier {
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

class _Players implements PlayerRepository {
  _Players(this.players, this.error);
  final List<Player> players;
  final Object? error;
  @override
  Future<List<Player>> getSquadPlayers({required String squadId}) async {
    if (error != null) throw error!;
    return players;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Fixture: ${invocation.memberName}');
}
