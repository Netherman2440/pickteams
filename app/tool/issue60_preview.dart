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

late final SemanticsHandle semantics;
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  semantics = SemanticsBinding.instance.ensureSemantics();
  GoogleFonts.config.allowRuntimeFetching = false;
  final query = Uri.base.queryParameters;
  final backend = SnapshotBackend(
    substitutes: query['substitutes'] == 'on',
    count: query['equal'] == '1' ? 4 : 5,
  );
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
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const MatchDetailsPage(squadId: 'fixture', matchId: 'match'),
      ),
    ],
  );
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
                    onPressed: () =>
                        ref.invalidate(matchDetailsProvider('match')),
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
