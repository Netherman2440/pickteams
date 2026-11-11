// Synthetic, credential-free real pages inside the unchanged RootShell.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';

import '../test/fixtures/lineup_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  SemanticsBinding.instance.ensureSemantics();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('F015_FLUTTER_ERROR: ${details.exceptionAsString()}');
  };
  final params = Uri.base.queryParameters;
  runApp(
    lineupFixture(
      page: params['page'] ?? 'match',
      count: int.tryParse(params['count'] ?? '') ?? 8,
      scale: double.tryParse(params['scale'] ?? '') ?? 1,
      longNames: params['long'] == 'true',
      savedScore: params['saved'] != 'false',
      role: params['reader'] == 'true' ? SquadRole.member : SquadRole.owner,
    ),
  );
}
