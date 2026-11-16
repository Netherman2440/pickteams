import '../services/player_goal_comparison.dart';

abstract class GoalComparisonRepository {
  Future<List<GoalComparisonMatch>> getSquadHistory(String squadId);
}
