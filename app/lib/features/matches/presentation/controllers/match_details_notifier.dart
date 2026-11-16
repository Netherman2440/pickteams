import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:app/features/matches/application/dto/match_details_dto.dart';
import 'package:app/features/matches/application/usecases/get_match_usecase.dart';
import 'package:app/features/matches/application/usecases/update_match_score_usecase.dart';
import 'package:app/features/matches/application/usecases/delete_match_usecase.dart';
import 'package:app/features/matches/application/usecases/update_match_team_usecase.dart';
import 'package:app/features/matches/application/usecases/update_match_teams_usecase.dart';
import 'package:app/features/matches/application/usecases/rematch_usecase.dart';
import 'package:app/features/players/presentation/controllers/player_details_controller.dart';

part 'match_details_notifier.g.dart';

@riverpod
class MatchDetailsNotifier extends _$MatchDetailsNotifier {
  UpdateMatchTeamsUseCase? get _rosterEdits =>
      ref.exists(updateMatchTeamsUseCaseProvider)
      ? ref.read(updateMatchTeamsUseCaseProvider)
      : null;
  bool get hasPendingRosterEdit =>
      _rosterEdits?.hasPendingEdit(matchId) ?? false;
  bool get hasRejectedRosterEdit =>
      _rosterEdits?.hasRejectedEdit(matchId) ?? false;

  @override
  AsyncValue<MatchDetailsDto> build(String matchId) {
    _loadMatch();
    return const AsyncValue.loading();
  }

  Future<void> _loadMatch() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return ref.read(getMatchUseCaseProvider).execute(matchId: matchId);
    });
  }

  Future<void> refresh() async {
    final edits = _rosterEdits;
    final rejectedId = edits?.rejectedRequestId(matchId);
    await _loadMatch();
    // A successful explicit reload acknowledges only the rejected operation
    // captured before that read. Never discard an unknown or newer outcome.
    if (state.hasValue &&
        !state.hasError &&
        rejectedId != null &&
        edits != null) {
      edits.discardRejected(matchId, requestId: rejectedId);
    }
  }

  Future<void> cancelRosterEdit() => refresh();

  Future<void> retryRosterEdit() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(updateMatchTeamsUseCaseProvider).retryPending(matchId);
      return ref.read(getMatchUseCaseProvider).execute(matchId: matchId);
    });
  }

  Future<void> updateScore(String squadId, int homeScore, int awayScore) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final updatedMatch = await ref
          .read(updateMatchScoreUseCaseProvider)
          .execute(
            matchId: matchId,
            squadId: squadId,
            homeScore: homeScore,
            awayScore: awayScore,
          );

      // Invalidate ranking history/player details for affected players so UI refreshes.
      final players = <String>{
        for (final p in updatedMatch.homeTeam?.players ?? const []) p.playerId,
        for (final p in updatedMatch.awayTeam?.players ?? const []) p.playerId,
      };
      for (final playerId in players) {
        ref.invalidate(playerDetailsProvider(playerId));
      }
      return updatedMatch;
    });
  }

  Future<void> updateTeams(
    List<String> homePlayerIds,
    List<String> awayPlayerIds,
  ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(updateMatchTeamsUseCaseProvider)
          .execute(
            matchId: matchId,
            homePlayerIds: homePlayerIds,
            awayPlayerIds: awayPlayerIds,
          );
      // Reload to get fresh state (rankings etc)
      return ref.read(getMatchUseCaseProvider).execute(matchId: matchId);
    });
  }

  Future<void> updateTeamsMeta({
    required String homeTeamId,
    required String awayTeamId,
    String? homeName,
    String? homeColor,
    String? awayName,
    String? awayColor,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      if (homeName != null || homeColor != null) {
        await ref
            .read(updateMatchTeamUseCaseProvider)
            .execute(
              matchId: matchId,
              teamId: homeTeamId,
              name: homeName,
              color: homeColor,
            );
      }
      if (awayName != null || awayColor != null) {
        await ref
            .read(updateMatchTeamUseCaseProvider)
            .execute(
              matchId: matchId,
              teamId: awayTeamId,
              name: awayName,
              color: awayColor,
            );
      }
      return ref.read(getMatchUseCaseProvider).execute(matchId: matchId);
    });
  }

  Future<MatchDetailsDto> rematch() async {
    // Returns the new match. UI handles navigation.
    final newMatch = await ref
        .read(rematchUseCaseProvider)
        .execute(matchId: matchId);
    return newMatch;
  }

  Future<void> deleteMatch() async {
    // We don't update state to data here because match is gone.
    // UI should listen and pop.
    // But we can set loading.
    state = const AsyncValue.loading();
    await AsyncValue.guard(() async {
      await ref.read(deleteMatchUseCaseProvider).execute(matchId: matchId);
      // We might return null or throw specific exception to signal deletion?
      // Or just let the UI handle the success of this future.
      // However, updating state to "data" is wrong if it doesn't exist.
      // We can leave it as loading or set error if failed.
    });
  }
}
