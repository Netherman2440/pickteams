import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import '../domain/match_level.dart';
import '../domain/repositories/match_level_repository.dart';

class SaveStarThresholds {
  const SaveStarThresholds(this.repository, {this.onSaved});
  final MatchLevelRepository repository;
  final void Function(String squadId)? onSaved;

  Future<void> execute({
    required String squadId,
    required SquadRole? role,
    required Iterable<double> values,
  }) async {
    if (role != SquadRole.owner) throw StateError('Brak uprawnień.');
    await repository.saveThresholds(squadId, MatchLevelThresholds(values));
    onSaved?.call(squadId);
  }
}
