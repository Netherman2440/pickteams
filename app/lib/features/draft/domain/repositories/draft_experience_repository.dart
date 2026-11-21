abstract class DraftExperienceRepository {
  /// Prior scored match memberships, counted once per player per match.
  Future<Map<String, int>> getAppearances({
    required List<String> playerIds,
    String? currentMatchId,
  });
}
