import '../match_level.dart';

class SquadMatchLevels {
  const SquadMatchLevels({required this.completedMatches, required this.means});
  final int completedMatches;
  final Map<String, double?> means;
}

abstract class MatchLevelRepository {
  Future<MatchLevelThresholds?> loadThresholds(String squadId);
  Future<void> saveThresholds(String squadId, MatchLevelThresholds thresholds);
  Future<SquadMatchLevels> loadHistory(String squadId);
}
