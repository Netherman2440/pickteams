// Synthetic atomic RPC transport only. PostgreSQL tests prove transactions/RLS.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'snapshot_backend.dart';

class AtomicRosterBackend extends SnapshotBackend {
  bool failBeforeCommit = false;
  bool loseReply = false;
  bool failNextMatchRead = false;
  void Function()? beforeRpc;
  Future<void> Function()? waitBeforeRpc;
  final commands = <Map<String, dynamic>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (failNextMatchRead &&
        request.method == 'GET' &&
        request.url.pathSegments.last == 'matches') {
      failNextMatchRead = false;
      requests.add('${request.method} ${request.url.path}');
      await request.finalize().drain<void>();
      return _failure(request);
    }
    if (!request.url.path.endsWith('/rpc/update_preserved_match_roster')) {
      return super.send(request);
    }
    requests.add('${request.method} ${request.url.path}');
    final input = Map<String, dynamic>.from(
      jsonDecode(await request.finalize().bytesToString()) as Map,
    );
    commands.add(input);
    await waitBeforeRpc?.call();
    beforeRpc?.call();
    final match = tables['matches']!.singleWhere(
      (m) => m['match_id'] == input['p_match_id'],
    );
    final meta = Map<String, dynamic>.from(match['score_meta'] as Map);
    final receipt = {
      'id': input['p_request_id'],
      'home': input['p_home'],
      'away': input['p_away'],
      'rankings': input['p_rankings'],
      'base': input['p_expected_version'],
    };
    final previous = meta['_roster_operation'] as Map?;
    if (previous?['id'] == input['p_request_id']) {
      if (jsonEncode(previous) != jsonEncode(receipt))
        return _failure(request, code: 'P0001');
      return _response(null, request);
    }
    if (match['home_score'] != null || match['away_score'] != null) {
      return _failure(request, code: 'P0001');
    }
    if (previous?['id'] != input['p_expected_version']) {
      return _failure(request, code: '40001');
    }
    final roster = <Map<String, dynamic>>[
      for (final side in ['home', 'away'])
        for (final id in input['p_$side'] as List)
          {'match_id': match['match_id'], 'team_id': side, 'player_id': id},
    ];
    if (failBeforeCommit) {
      failBeforeCommit = false;
      return _failure(request);
    }
    tables['team_players'] = roster;
    match['score_meta'] = {
      ...meta,
      'draft_rankings': input['p_rankings'],
      '_roster_operation': receipt,
    };
    if (loseReply) {
      loseReply = false;
      return _failure(request);
    }
    return _response(null, request);
  }

  http.StreamedResponse _failure(
    http.BaseRequest request, {
    String code = 'fixture_failure',
  }) => _response(
    {'code': code, 'message': 'Injected atomic RPC failure'},
    request,
    status: 400,
  );

  http.StreamedResponse _response(
    Object? value,
    http.BaseRequest request, {
    int status = 200,
  }) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(value))),
    status,
    headers: {'content-type': 'application/json'},
    request: request,
  );
}
