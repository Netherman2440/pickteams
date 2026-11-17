// SYNTHETIC HTTP/browser fixture. Not imported by the production entrypoint.
import 'dart:convert';
import 'package:app/core/app_router.dart';
import 'package:app/core/app_theme.dart';
import 'package:app/features/matches/application/match_level_providers.dart';
import 'package:app/features/matches/application/usecases/get_match_usecase.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/team.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/matches/domain/repositories/match_repository.dart';
import 'package:app/features/matches/infrastructure/repositories/supabase_match_level_repository.dart';
import 'package:app/features/matches/infrastructure/repositories/supabase_team_repository.dart';
import 'package:app/features/matches/presentation/controllers/squad_matches_notifier.dart';
import 'package:app/features/matches/presentation/pages/match_details_page.dart';
import 'package:app/features/matches/presentation/pages/squad_matches_page.dart';
import 'package:app/features/squads/domain/entities/squad.dart';
import 'package:app/features/squads/domain/entities/squad_member.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/pages/squad_settings_page.dart';
import 'package:app/features/squads/presentation/pages/squad_star_thresholds_page.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:app/features/squads/presentation/state/squad_invite_link_provider.dart';
import 'package:app/features/squads/presentation/state/squad_settings_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'historical_match_data.dart';

class MatchLevelData {
  MatchLevelData({
    this.completed = 26,
    this.role = SquadRole.owner,
    bool configured = true,
  }) {
    thresholds = configured ? [10, 20, 40, 70, 120] : null;
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-key',
      httpClient: MockClient(_respond),
    );
  }
  int completed;
  final SquadRole? role;
  final lineup = HistoricalMatchData();
  late final SupabaseClient client;
  List<num>? thresholds;
  bool failLoad = false;
  bool failSave = false;
  bool hasResult = true;
  int saves = 0;
  final requests = <String>[];

  Match get match => Match(
    matchId: 'match',
    squadId: 'fixture',
    createdAt: DateTime(2026, 11, 13),
    homeScore: hasResult ? 3 : null,
    awayScore: hasResult ? 1 : null,
    homeWinProbability: .6,
    homeTeam: Team(
      teamId: 'home',
      matchId: 'match',
      side: Side.home,
      name: 'Zieloni',
      color: '#81B64C',
      playerCount: 2,
    ),
    awayTeam: Team(
      teamId: 'away',
      matchId: 'match',
      side: Side.away,
      name: 'Niebiescy',
      color: '#1E88E5',
      playerCount: 2,
    ),
  );
  Future<http.Response> _respond(http.Request r) async {
    requests.add('${r.method} ${r.url.pathSegments.last}');
    if ((failLoad && r.method == 'GET') || (failSave && r.method == 'PATCH')) {
      return http.Response('{"message":"fixture failure"}', 403, request: r);
    }
    Object? rows;
    switch (r.url.pathSegments.last) {
      case 'squads':
        if (r.method == 'PATCH') {
          thresholds = (jsonDecode(r.body)['star_thresholds'] as List)
              .cast<num>();
          saves++;
          rows = {'squad_id': 'fixture'};
        } else {
          rows = {'star_thresholds': thresholds};
        }
      case 'matches':
        rows = [
          for (var i = 0; i < completed; i++)
            {
              'match_id': hasResult && i == 0 ? 'match' : 'm$i',
              'home_score': 3,
              'away_score': 1,
            },
          {
            'match_id': hasResult ? 'pending' : 'match',
            'home_score': null,
            'away_score': null,
          },
        ];
      case 'team_players':
        rows = [
          for (final id in ['p0', 'p1', 'p2', 'p3'])
            {'match_id': 'match', 'player_id': id},
        ];
      case 'ranking_history':
        rows = [
          for (final e in lineup.snapshots.entries.where((e) => e.key != 'p4'))
            {'match_id': 'match', 'player_id': e.key, 'ranking': e.value},
        ];
      default:
        throw StateError('Unexpected fixture request');
    }
    return http.Response(
      jsonEncode(rows),
      200,
      headers: {'content-type': 'application/json'},
      request: r,
    );
  }

  GetMatchUseCase get reader =>
      GetMatchUseCase(_Read(this), SupabaseTeamRepository(lineup.client));

  Future<void> dispose() async {
    await client.dispose();
    await lineup.client.dispose();
  }
}

class _Matches extends SquadMatchesNotifier {
  _Matches(this.data);
  final MatchLevelData data;
  @override
  AsyncValue<List<Match>> build(String squadId) => AsyncData([data.match]);
}

class _Members extends SquadSettingsNotifier {
  @override
  Future<List<SquadMember>> build() async => [];
  @override
  Future<void> load(String squadId) async {}
}

class _Read implements MatchRepository {
  _Read(this.data);
  final MatchLevelData data;
  @override
  Future<Match> getMatch({required String matchId}) async => data.match;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MatchLevelApp extends StatefulWidget {
  const MatchLevelApp({
    super.key,
    required this.data,
    this.screen = 'list',
    this.retainList = false,
    this.providerOverrides = const [],
  });
  final MatchLevelData data;
  final String screen;
  final bool retainList;
  final List<Override> providerOverrides;
  @override
  State<MatchLevelApp> createState() => _MatchLevelAppState();
}

class _MatchLevelAppState extends State<MatchLevelApp> {
  late final router = GoRouter(
    initialLocation: switch (widget.screen) {
      'details' => '/squads/fixture/matches/match',
      'settings' => '/squads/fixture/settings',
      'stars' => '/squads/fixture/settings/stars',
      _ => '/squads/fixture/matches',
    },
    routes: [
      GoRoute(
        path: '/squads/:squadId/matches',
        name: AppRoute.matches.name,
        builder: (_, _) => const SquadMatchesPage(squadId: 'fixture'),
      ),
      GoRoute(
        path: '/squads/:squadId/matches/:matchId',
        name: AppRoute.matchDetails.name,
        builder: (_, _) =>
            const MatchDetailsPage(squadId: 'fixture', matchId: 'match'),
      ),
      GoRoute(
        path: '/squads/:squadId/settings',
        name: AppRoute.settings.name,
        builder: (_, _) => const SquadSettingsPage(squadId: 'fixture'),
      ),
      GoRoute(
        path: '/squads/:squadId/settings/stars',
        name: AppRoute.starThresholds.name,
        builder: (_, _) => const SquadStarThresholdsPage(squadId: 'fixture'),
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
      matchLevelRepositoryProvider.overrideWithValue(
        SupabaseMatchLevelRepository(widget.data.client),
      ),
      squadMatchesProvider.overrideWith(() => _Matches(widget.data)),
      getMatchUseCaseProvider.overrideWithValue(widget.data.reader),
      squadDetailProvider.overrideWith(
        (ref, id) async => Squad(
          squadId: id,
          ownerId: 'synthetic',
          name: 'SYNTHETIC',
          visibility: SquadVisibility.private,
          sportType: SportType.football,
          role: widget.data.role ?? SquadRole.none,
          createdAt: DateTime(2026),
        ),
      ),
      squadSettingsProvider.overrideWith(_Members.new),
      squadInviteLinkProvider.overrideWith((ref, id) async => null),
      ...widget.providerOverrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.darkTheme,
      routerConfig: router,
      builder: (context, child) => Column(
        children: [
          const Material(
            color: Colors.amber,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  'SYNTHETIC browser fixture — not production',
                  style: TextStyle(color: Colors.black, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Expanded(child: child!),
          if (widget.retainList)
            Offstage(
              child: SizedBox(
                width: 600,
                height: 1000,
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const SquadMatchesPage(squadId: 'fixture'),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
