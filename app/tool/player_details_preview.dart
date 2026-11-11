// Explicit credential-free entry point for profile visual proof.
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../test/fixtures/player_details_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  final params = Uri.base.queryParameters;
  runApp(
    PlayerDetailsFixture(
      data: ProfileFixtureData(
        longName: params['long'] == 'true',
        fail: params['fail'] == 'true',
      ),
      role: params['role'] == 'viewer' ? SquadRole.none : SquadRole.owner,
      textScale: double.tryParse(params['scale'] ?? '') ?? 1,
    ),
  );
}
