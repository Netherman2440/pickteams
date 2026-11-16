import 'package:app/core/error/failure.dart';

/// A PostgreSQL rejection confirms that the atomic roster write did not commit.
/// Transport/unknown errors must not be classified as this failure.
class RosterEditRejected extends Failure {
  const RosterEditRejected(super.message, super.code);
}
