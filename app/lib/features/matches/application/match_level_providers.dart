import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/global_dependencies.dart';
import '../domain/match_level.dart';
import 'save_star_thresholds.dart';
import '../domain/repositories/match_level_repository.dart';
import '../infrastructure/repositories/supabase_match_level_repository.dart';
import '../presentation/controllers/squad_matches_notifier.dart';

final matchLevelRepositoryProvider = Provider<MatchLevelRepository>(
  (ref) => SupabaseMatchLevelRepository(ref.watch(supabaseProvider)),
);

final starThresholdsProvider = FutureProvider.autoDispose
    .family<MatchLevelThresholds?, String>(
      (ref, squadId) =>
          ref.watch(matchLevelRepositoryProvider).loadThresholds(squadId),
      // The settings page owns an explicit retry. Do not mask failures behind
      // Riverpod's delayed retry/loading state in the browser.
      retry: (retryCount, error) => null,
    );

// Keep successful-save invalidation alive when the editor leaves the tree.
// Capture the saved squad in the use case, never from a later widget state.
final saveStarThresholdsProvider = Provider<SaveStarThresholds>((ref) {
  return SaveStarThresholds(
    ref.read(matchLevelRepositoryProvider),
    onSaved: (squadId) {
      if (ref.mounted) {
        ref.invalidate(starThresholdsProvider(squadId));
      }
    },
  );
});

final squadMatchLevelsProvider = FutureProvider.autoDispose
    .family<Map<String, double>, String>((ref, squadId) async {
      // Result/roster refreshes must update eligibility and historical completeness.
      ref.watch(squadMatchesProvider(squadId));
      final thresholds =
          await ref.watch(starThresholdsProvider(squadId).future) ??
          MatchLevelThresholds.calibratedBaseline;
      final history = await ref
          .watch(matchLevelRepositoryProvider)
          .loadHistory(squadId);
      if (!matchLevelEligible(history.completedMatches)) return const {};
      return {
        for (final entry in history.means.entries)
          if (entry.value != null) entry.key: thresholds.rating(entry.value!),
      };
    });
