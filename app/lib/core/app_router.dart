import 'package:go_router/go_router.dart';

import 'package:app/features/players/presentation/pages/player_details_page.dart';
import 'package:app/features/players/presentation/pages/player_matches_page.dart';
import 'package:app/features/players/presentation/pages/player_stats_page.dart';
import 'package:app/features/players/presentation/pages/player_tournaments_page.dart';
import 'package:app/core/root_shell.dart';
import 'package:app/features/auth/presentation/pages/auth_page.dart';
import 'package:app/features/auth/presentation/pages/auth_confirm_page.dart';
import 'package:app/features/auth/presentation/pages/auth_callback_page.dart';
import 'package:app/features/auth/presentation/pages/register_page.dart';
import 'package:app/features/auth/presentation/pages/reset_password_page.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/presentation/pages/draft_against_relations_page.dart';
import 'package:app/features/draft/presentation/pages/draft_relations_page.dart';
import 'package:app/features/draft/presentation/pages/draft_results_page.dart';
import 'package:app/features/draft/presentation/pages/draft_selection_page.dart';
import 'package:app/features/landing/presentation/pages/landing_page.dart';
import 'package:app/features/squads/presentation/pages/invite_page.dart';
import 'package:app/features/matches/presentation/pages/match_details_page.dart';
import 'package:app/features/matches/presentation/pages/squad_matches_page.dart';
import 'package:app/features/squads/presentation/pages/squad_ranking_settings_page.dart';
import 'package:app/features/squads/presentation/pages/squad_settings_page.dart';
import 'package:app/features/squads/presentation/pages/squad_stats_page.dart';
import 'package:app/features/players/presentation/pages/players_page.dart';
import 'package:app/features/squads/presentation/pages/squads_page.dart';
import 'package:app/features/users/presentation/pages/user_page.dart';
import 'package:app/features/squads/presentation/pages/squad_shell_page.dart';
import 'package:app/features/tournaments/presentation/pages/create_tournament_page.dart';
import 'package:app/features/tournaments/presentation/pages/squad_tournaments_page.dart';
import 'package:app/features/tournaments/presentation/pages/tournament_against_relations_page.dart';
import 'package:app/features/tournaments/presentation/pages/tournament_details_page.dart';
import 'package:app/features/tournaments/presentation/pages/tournament_draft_page.dart';
import 'package:app/features/tournaments/presentation/pages/tournament_relations_page.dart';
import 'package:app/features/tournaments/presentation/pages/tournament_teams_page.dart';

enum AppRoute {
  landing,
  auth,
  authRegister,
  authConfirm,
  authCallback,
  authReset,
  squads,
  settings,
  rankingSettings,
  squadStats,
  profile,
  squadDetails,
  players,
  draftSelection,
  draftPreview,
  draftCreate,
  draftRelations,
  draftAgainstRelations,
  matchDraft,
  playerDetails,
  playerMatches,
  playerTournaments,
  playerStats,
  matches,
  matchDetails,
  tournaments,
  tournamentCreate,
  tournamentDraftRelations,
  tournamentDraftAgainstRelations,
  tournamentDraft,
  tournamentDetails,
  tournamentTeams,
  tournamentDraftById,
  invite,
}

final appRouter = () {
  // Ensure imperative navigation (push/pushNamed) updates the URL on Flutter Web.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: AppRoute.landing.name,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: LandingPage()),
      ),
      GoRoute(
        path: '/auth',
        name: AppRoute.auth.name,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: AuthPage()),
      ),
      GoRoute(
        path: '/auth/confirm',
        name: AppRoute.authConfirm.name,
        pageBuilder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return NoTransitionPage(child: AuthConfirmPage(email: email));
        },
      ),
      GoRoute(
        path: '/auth/callback',
        name: AppRoute.authCallback.name,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: AuthCallbackPage()),
      ),
      GoRoute(
        path: '/auth/reset',
        name: AppRoute.authReset.name,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: ResetPasswordPage()),
      ),
      GoRoute(
        path: '/invite',
        name: AppRoute.invite.name,
        pageBuilder: (context, state) {
          final code = state.uri.queryParameters['code'];
          return NoTransitionPage(child: InvitePage(code: code));
        },
      ),
      GoRoute(
        path: '/auth/register',
        name: AppRoute.authRegister.name,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: RegisterPage()),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            RootShell(location: state.uri.toString(), child: child),
        routes: [
          GoRoute(
            path: '/squads',
            name: AppRoute.squads.name,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SquadsPage()),
          ),
          GoRoute(
            path: '/squads/:squadId',
            name: AppRoute.squadDetails.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              return NoTransitionPage(child: SquadShellPage(squadId: squadId));
            },
          ),
          GoRoute(
            path: '/squads/:squadId/players',
            name: AppRoute.players.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              return NoTransitionPage(child: PlayersPage(squadId: squadId));
            },
          ),
          GoRoute(
            path: '/squads/:squadId/players/:playerId',
            name: AppRoute.playerDetails.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final playerId = state.pathParameters['playerId'] ?? '';
              return NoTransitionPage(
                child: PlayerDetailsPage(squadId: squadId, playerId: playerId),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/players/:playerId/matches',
            name: AppRoute.playerMatches.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final playerId = state.pathParameters['playerId'] ?? '';
              return NoTransitionPage(
                child: PlayerMatchesPage(squadId: squadId, playerId: playerId),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/players/:playerId/tournaments',
            name: AppRoute.playerTournaments.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final playerId = state.pathParameters['playerId'] ?? '';
              return NoTransitionPage(
                child: PlayerTournamentsPage(
                  squadId: squadId,
                  playerId: playerId,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/players/:playerId/stats',
            name: AppRoute.playerStats.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final playerId = state.pathParameters['playerId'] ?? '';
              return NoTransitionPage(
                child: PlayerStatsPage(squadId: squadId, playerId: playerId),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/matches',
            name: AppRoute.matches.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              return NoTransitionPage(
                child: SquadMatchesPage(squadId: squadId),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/stats',
            name: AppRoute.squadStats.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              return NoTransitionPage(child: SquadStatsPage(squadId: squadId));
            },
          ),
          GoRoute(
            path: '/squads/:squadId/matches/draft',
            name: AppRoute.draftSelection.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final extra = state.extra;

              List<String> selectedIds = const [];
              String? matchId;
              List<DraftRule> draftRules = const [];

              if (extra is Map<String, dynamic>) {
                selectedIds =
                    (extra['selectedIds'] as List<dynamic>?)?.cast<String>() ??
                    [];
                matchId = extra['matchId'] as String?;
                draftRules = _decodeDraftRules(extra['draftRules']);
              }

              return NoTransitionPage(
                child: DraftSelectionPage(
                  squadId: squadId,
                  initialSelectedIds: selectedIds,
                  initialDraftRules: draftRules,
                  matchId: matchId,
                  playWithSubstitute: extra is Map<String, dynamic>
                      ? (extra['playWithSubstitute'] as bool?) ?? true
                      : true,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/matches/preview',
            name: AppRoute.draftPreview.name,
            pageBuilder: (context, state) {
              final extra = state.extra as Map<String, dynamic>? ?? {};
              return NoTransitionPage(
                child: DraftResultsPage(
                  squadId: state.pathParameters['squadId'] ?? '',
                  selectedPlayerIds:
                      (extra['selectedIds'] as List<dynamic>?)
                          ?.cast<String>() ??
                      [],
                  draftRules: _decodeDraftRules(extra['draftRules']),
                  playWithSubstitute:
                      (extra['playWithSubstitute'] as bool?) ?? true,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/matches/create',
            name: AppRoute.draftCreate.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final extra = state.extra;

              List<String> selectedIds = const [];
              String? matchId;
              List<DraftRule> draftRules = const [];
              if (extra is List<String>) {
                selectedIds = extra;
              } else if (extra is Map<String, dynamic>) {
                selectedIds =
                    (extra['selectedIds'] as List<dynamic>?)?.cast<String>() ??
                    [];
                matchId = extra['matchId'] as String?;
                draftRules = _decodeDraftRules(extra['draftRules']);
              }

              return NoTransitionPage(
                child: DraftSelectionPage(
                  squadId: squadId,
                  initialSelectedIds: selectedIds,
                  initialDraftRules: draftRules,
                  matchId: matchId,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/matches/relations',
            name: AppRoute.draftRelations.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final extra = state.extra;

              List<String> selectedIds = const [];
              String? matchId;
              var playWithSubstitute = true;
              List<DraftRule> draftRules = const [];

              if (extra is Map<String, dynamic>) {
                selectedIds =
                    (extra['selectedIds'] as List<dynamic>?)?.cast<String>() ??
                    [];
                matchId = extra['matchId'] as String?;
                playWithSubstitute =
                    (extra['playWithSubstitute'] as bool?) ?? true;
                draftRules = _decodeDraftRules(extra['draftRules']);
              }

              return NoTransitionPage(
                child: DraftRelationsPage(
                  squadId: squadId,
                  selectedPlayerIds: selectedIds,
                  initialDraftRules: draftRules,
                  matchId: matchId,
                  playWithSubstitute: playWithSubstitute,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/matches/relations/against',
            name: AppRoute.draftAgainstRelations.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final extra = state.extra;

              List<String> selectedIds = const [];
              String? matchId;
              var playWithSubstitute = true;
              List<DraftRule> draftRules = const [];

              if (extra is Map<String, dynamic>) {
                selectedIds =
                    (extra['selectedIds'] as List<dynamic>?)?.cast<String>() ??
                    [];
                matchId = extra['matchId'] as String?;
                playWithSubstitute =
                    (extra['playWithSubstitute'] as bool?) ?? true;
                draftRules = _decodeDraftRules(extra['draftRules']);
              }

              return NoTransitionPage(
                child: DraftAgainstRelationsPage(
                  squadId: squadId,
                  selectedPlayerIds: selectedIds,
                  initialDraftRules: draftRules,
                  matchId: matchId,
                  playWithSubstitute: playWithSubstitute,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/matches/:matchId/draft',
            name: AppRoute.matchDraft.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final matchId = state.pathParameters['matchId'] ?? '';
              final extra = state.extra;

              List<String> selectedIds = const [];
              var playWithSubstitute = true;
              List<DraftRule> draftRules = const [];
              if (extra is List<String>) {
                selectedIds = extra;
              } else if (extra is Map<String, dynamic>) {
                selectedIds =
                    (extra['selectedIds'] as List<dynamic>?)?.cast<String>() ??
                    [];
                playWithSubstitute =
                    (extra['playWithSubstitute'] as bool?) ?? true;
                draftRules = _decodeDraftRules(extra['draftRules']);
              }

              return NoTransitionPage(
                child: DraftResultsPage(
                  squadId: squadId,
                  selectedPlayerIds: selectedIds,
                  draftRules: draftRules,
                  matchId: matchId,
                  playWithSubstitute: playWithSubstitute,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/matches/:matchId',
            name: AppRoute.matchDetails.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final matchId = state.pathParameters['matchId'] ?? '';
              return NoTransitionPage(
                child: MatchDetailsPage(squadId: squadId, matchId: matchId),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/tournaments',
            name: AppRoute.tournaments.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              return NoTransitionPage(
                child: SquadTournamentsPage(squadId: squadId),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/tournaments/create',
            name: AppRoute.tournamentCreate.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              return NoTransitionPage(
                child: CreateTournamentPage(squadId: squadId),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/tournaments/:tournamentId/draft/relations',
            name: AppRoute.tournamentDraftRelations.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final tournamentId = state.pathParameters['tournamentId'] ?? '';
              final extra = state.extra;

              List<String> selectedIds = const [];
              var teamCount = 2;
              List<DraftRule> draftRules = const [];

              if (extra is Map<String, dynamic>) {
                selectedIds =
                    (extra['selectedIds'] as List<dynamic>?)?.cast<String>() ??
                    [];
                teamCount = (extra['teamCount'] as int?) ?? 2;
                draftRules = _decodeDraftRules(extra['draftRules']);
              }

              return NoTransitionPage(
                child: TournamentRelationsPage(
                  squadId: squadId,
                  tournamentId: tournamentId,
                  selectedPlayerIds: selectedIds,
                  teamCount: teamCount,
                  initialDraftRules: draftRules,
                ),
              );
            },
          ),
          GoRoute(
            path:
                '/squads/:squadId/tournaments/:tournamentId/draft/relations/against',
            name: AppRoute.tournamentDraftAgainstRelations.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final tournamentId = state.pathParameters['tournamentId'] ?? '';
              final extra = state.extra;

              List<String> selectedIds = const [];
              var teamCount = 2;
              List<DraftRule> draftRules = const [];

              if (extra is Map<String, dynamic>) {
                selectedIds =
                    (extra['selectedIds'] as List<dynamic>?)?.cast<String>() ??
                    [];
                teamCount = (extra['teamCount'] as int?) ?? 2;
                draftRules = _decodeDraftRules(extra['draftRules']);
              }

              return NoTransitionPage(
                child: TournamentAgainstRelationsPage(
                  squadId: squadId,
                  tournamentId: tournamentId,
                  selectedPlayerIds: selectedIds,
                  teamCount: teamCount,
                  initialDraftRules: draftRules,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/tournaments/:tournamentId/draft',
            name: AppRoute.tournamentDraft.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final tournamentId = state.pathParameters['tournamentId'] ?? '';
              final extra = state.extra;

              List<String> selectedIds = const [];
              var teamCount = 2;
              List<DraftRule> draftRules = const [];

              if (extra is Map<String, dynamic>) {
                selectedIds =
                    (extra['selectedIds'] as List<dynamic>?)?.cast<String>() ??
                    [];
                teamCount = (extra['teamCount'] as int?) ?? 2;
                draftRules = _decodeDraftRules(extra['draftRules']);
              }

              return NoTransitionPage(
                child: TournamentDraftPage(
                  squadId: squadId,
                  tournamentId: tournamentId,
                  selectedPlayerIds: selectedIds,
                  teamCount: teamCount,
                  draftRules: draftRules,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/tournaments/:tournamentId/teams',
            name: AppRoute.tournamentTeams.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final tournamentId = state.pathParameters['tournamentId'] ?? '';
              return NoTransitionPage(
                child: TournamentTeamsPage(
                  squadId: squadId,
                  tournamentId: tournamentId,
                ),
              );
            },
          ),
          GoRoute(
            path:
                '/squads/:squadId/tournaments/:tournamentId/drafts/:tournamentDraftId',
            name: AppRoute.tournamentDraftById.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final tournamentId = state.pathParameters['tournamentId'] ?? '';
              final tournamentDraftId =
                  state.pathParameters['tournamentDraftId'] ?? '';

              return NoTransitionPage(
                child: TournamentDraftPage(
                  squadId: squadId,
                  tournamentId: tournamentId,
                  tournamentDraftId: tournamentDraftId,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/tournaments/:tournamentId',
            name: AppRoute.tournamentDetails.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              final tournamentId = state.pathParameters['tournamentId'] ?? '';
              return NoTransitionPage(
                child: TournamentDetailsPage(
                  squadId: squadId,
                  tournamentId: tournamentId,
                ),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/settings',
            name: AppRoute.settings.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              return NoTransitionPage(
                child: SquadSettingsPage(squadId: squadId),
              );
            },
          ),
          GoRoute(
            path: '/squads/:squadId/settings/ranking',
            name: AppRoute.rankingSettings.name,
            pageBuilder: (context, state) {
              final squadId = state.pathParameters['squadId'] ?? '';
              return NoTransitionPage(
                child: SquadRankingSettingsPage(squadId: squadId),
              );
            },
          ),
          GoRoute(
            path: '/me',
            name: AppRoute.profile.name,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: UserPage()),
          ),
        ],
      ),
    ],
  );
}();

List<DraftRule> _decodeDraftRules(Object? rawRules) {
  if (rawRules is! List) {
    return const [];
  }

  final rules = <DraftRule>[];
  for (final entry in rawRules) {
    if (entry is! Map) {
      continue;
    }
    final typeRaw = entry['type'];
    final playerIdsRaw = entry['playerIds'];
    if (typeRaw is! String || playerIdsRaw is! List) {
      continue;
    }

    final type = switch (typeRaw) {
      'together' => DraftRuleType.together,
      'against' => DraftRuleType.against,
      _ => null,
    };
    if (type == null) {
      continue;
    }

    final ids = playerIdsRaw.whereType<String>().toList(growable: false);
    if (ids.length < 2) {
      continue;
    }

    rules.add(DraftRule(type: type, playerIds: ids));
  }

  return rules;
}
