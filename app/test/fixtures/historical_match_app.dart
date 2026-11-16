import 'package:app/core/app_theme.dart';
import 'package:app/features/matches/application/usecases/get_match_usecase.dart';
import 'package:app/features/matches/presentation/controllers/match_details_notifier.dart';
import 'package:app/features/matches/presentation/pages/match_details_page.dart';
import 'package:app/features/squads/domain/entities/squad.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'historical_match_data.dart';

class HistoricalMatchApp extends StatefulWidget {
  const HistoricalMatchApp({super.key, required this.data});
  final HistoricalMatchData data;
  @override
  State<HistoricalMatchApp> createState() => _HistoricalMatchAppState();
}

class _HistoricalMatchAppState extends State<HistoricalMatchApp> {
  late final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const MatchDetailsPage(squadId: 'fixture', matchId: 'match'),
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
      getMatchUseCaseProvider.overrideWithValue(widget.data.reader),
      squadDetailProvider.overrideWith(
        (ref, id) async => Squad(
          squadId: id,
          ownerId: 'synthetic',
          name: 'SYNTHETIC',
          visibility: SquadVisibility.private,
          sportType: SportType.football,
          role: SquadRole.member,
          createdAt: DateTime(2026),
        ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.darkTheme,
      routerConfig: router,
      builder: (context, child) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Consumer(
                builder: (context, ref, _) => ColoredBox(
                  color: Colors.amber,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'SYNTHETIC | ${widget.data.unequal ? "3 vs 2 (x2/3)" : "2 vs 2"} | '
                          '${["before result", "after result", "correction", "later current score"][widget.data.stage]} | '
                          'Current p0: ${widget.data.scores["p0"]!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.data.stage == 3
                            ? null
                            : () async {
                                await widget.data.advance();
                                await ref
                                    .read(
                                      matchDetailsProvider('match').notifier,
                                    )
                                    .refresh();
                                setState(() {});
                              },
                        child: const Text('Next state'),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(matchDetailsProvider('match').notifier)
                            .refresh(),
                        child: const Text('Reload'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: child!),
            ],
          ),
        ),
      ),
    ),
  );
}
