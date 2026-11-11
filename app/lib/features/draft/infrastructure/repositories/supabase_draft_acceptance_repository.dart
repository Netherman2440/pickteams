import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/features/draft/domain/repositories/draft_acceptance_repository.dart';

class SupabaseDraftAcceptanceRepository implements DraftAcceptanceRepository {
  SupabaseDraftAcceptanceRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<String> accept({
    required String requestId,
    required String squadId,
    String? matchId,
    required Map<String, dynamic> payload,
  }) async {
    // No fallback: older servers must reject acceptance, not create partial data.
    return await _client.rpc(
          'accept_match_draft',
          params: {
            'p_request_id': requestId,
            'p_squad_id': squadId,
            'p_match_id': matchId,
            'p_payload': payload,
          },
        )
        as String;
  }
}

final draftAcceptanceRepositoryProvider = Provider<DraftAcceptanceRepository>(
  (ref) => SupabaseDraftAcceptanceRepository(ref.read(supabaseProvider)),
);
