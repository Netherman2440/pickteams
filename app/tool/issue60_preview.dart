// Actual MatchDetailsPage and repositories, synthetic in-memory HTTP transport.
// No credentials, real network requests, production data, or RLS emulation.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/core/app_theme.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/features/draft/presentation/pages/draft_results_page.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/matches/presentation/controllers/match_details_notifier.dart';
import 'package:app/features/matches/presentation/pages/match_details_page.dart';
import '../test/fixtures/snapshot_backend.dart';
import '../test/fixtures/atomic_roster_backend.dart';

late final SemanticsHandle semantics;
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  semantics = SemanticsBinding.instance.ensureSemantics();
  GoogleFonts.config.allowRuntimeFetching = false;
  final query = Uri.base.queryParameters;
  final recovery = query['recovery'];
  final SnapshotBackend backend = ['conflict', 'uncertain'].contains(recovery)
      ? AtomicRosterBackend()
      : SnapshotBackend(
          substitutes: query['substitutes'] == 'on',
          count: query['equal'] == '1' ? 4 : 5,
        );
  if (backend is AtomicRosterBackend) {
    final match = backend.tables['matches']!.single;
    match['tournament_id'] = 'synthetic-tournament';
    match['score_meta'] = {
      'draft_rankings': {
        for (final p in backend.tables['players']!) p['player_id']: p['score'],
      },
    };
    backend.tables['ranking_history']!.clear();
    if (recovery == 'conflict') {
      backend.beforeRpc = () {
        backend.beforeRpc = null;
        for (final row in backend.tables['team_players']!) {
          if (row['player_id'] == 'p0') row['team_id'] = 'away';
        }
        match['score_meta']['_roster_operation'] = {
          'id': 'synthetic-other-operation',
          'home': ['p1'],
          'away': ['p0', 'p2', 'p3', 'p4'],
          'rankings': match['score_meta']['draft_rankings'],
          'base': null,
        };
      };
    } else {
      backend.loseReply = true;
    }
  }
  // A stored generation proposal and the accepted fixture match share A.
  // Current players then move to B. Both real pages must still display A.
  backend.tables['drafts']!.add({
    'draft_id': 'draft',
    'match_id': 'match',
    'status': 'completed',
    'team_count': 2,
    'proposals_count': 1,
  });
  backend.tables['draft_payloads']!.add({
    'draft_id': 'draft',
    'proposals': [
      {
        'teams': [
          ['p0', 'p1'],
          [for (var i = 2; i < backend.tables['players']!.length; i++) 'p$i'],
        ],
        'rankings': {
          for (final p in backend.tables['players']!)
            p['player_id']: p['score'],
        },
        'play_with_substitute': query['substitutes'] == 'on',
      },
    ],
    'win_rate_matrix': <String, dynamic>{},
  });
  backend.changeCurrentScores();
  runApp(
    ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(backend.client),
        authStateProvider.overrideWith(_FixtureAuth.new),
      ],
      child: _Preview(backend),
    ),
  );
}

class _FixtureAuth extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() => AsyncData(
    AuthEntity(
      accessToken: 'fixture',
      refreshToken: 'fixture',
      userId: 'owner',
      isAnonymous: false,
      email: 'owner@example.test',
    ),
  );
}

class _Preview extends ConsumerStatefulWidget {
  const _Preview(this.backend);
  final SnapshotBackend backend;
  @override
  ConsumerState<_Preview> createState() => _PreviewState();
}

class _PreviewState extends ConsumerState<_Preview> {
  late final router = GoRouter(
    routes: [
      GoRoute(
        path: '/proposal',
        builder: (_, _) => const DraftResultsPage(
          squadId: 'fixture',
          selectedPlayerIds: [],
          matchId: 'match',
        ),
      ),
      GoRoute(path: '/', builder: (_, _) => _matchPage()),
    ],
  );
  Widget _matchPage() {
    final backend = widget.backend;
    if (backend is! AtomicRosterBackend) {
      return const MatchDetailsPage(squadId: 'fixture', matchId: 'match');
    }
    return Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(matchDetailsProvider('match'));
        final controller = ref.read(matchDetailsProvider('match').notifier);
        final last = backend.commands.isEmpty ? null : backend.commands.last;
        return Column(
          children: [
            Material(
              color: const Color(0xFFE0F2F1),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Text(
                      'SYNTHETIC roster fixture / RPC ${backend.commands.length} '
                      'id=${last?['p_request_id'] ?? 'none'} '
                      'base=${last?['p_expected_version'] ?? 'initial'} '
                      'pending=${controller.hasPendingRosterEdit} '
                      'state=${state.isLoading
                          ? 'loading'
                          : state.hasError
                          ? 'error'
                          : 'loaded'}',
                    ),
                    TextButton(
                      onPressed: state.isLoading
                          ? null
                          : () => controller.updateTeams(
                              ['p0', 'p2'],
                              ['p1', 'p3', 'p4'],
                            ),
                      child: const Text('Synthetic roster save'),
                    ),
                  ],
                ),
              ),
            ),
            const Expanded(
              child: MatchDetailsPage(squadId: 'fixture', matchId: 'match'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    widget.backend.onWrite = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    router.dispose();
    widget.backend.onWrite = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    theme: AppTheme.lightTheme,
    routerConfig: router,
    builder: (context, child) => Column(
      children: [
        Material(
          color: const Color(0xFFFFECB3),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'FIXTURE / browser emulation — issue #60\n'
                      'Current scores (not match inputs): ${widget.backend.tables['players']!.map((p) => '${p['name']} ${p['score']}').join(', ')}',
                      style: const TextStyle(fontSize: 13, color: Colors.black),
                    ),
                  ),
                  TextButton(
                    onPressed: () => router.go('/proposal'),
                    child: const Text('Proposal'),
                  ),
                  TextButton(
                    onPressed: () => router.go('/'),
                    child: const Text('Match'),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(matchDetailsProvider('match').notifier)
                        .refresh(),
                    child: const Text('Reload match'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child!),
      ],
    ),
  );
}
