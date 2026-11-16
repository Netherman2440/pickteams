// Synthetic-only entrypoint. Not imported by lib/main.dart.
import 'dart:convert';
import 'dart:js_interop';

import 'package:app/features/matches/presentation/widgets/match_view_roster.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../test/fixtures/historical_match_app.dart';
import '../test/fixtures/historical_match_data.dart';

@JS('historicalMatchMetrics')
external set _metrics(JSFunction callback);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  SemanticsBinding.instance.ensureSemantics();
  final data = HistoricalMatchData(
    unequal: Uri.base.queryParameters['unequal'] == 'true',
  );
  _metrics = (() {
    final panels = <Object?>[];
    final labels = <String>[];
    void visit(Element element) {
      if (element.widget case final MatchViewPlayerPanel panel) {
        panels.add({
          'id': panel.player.playerId,
          'ranking': panel.player.ranking,
        });
      }
      if (element is RenderObjectElement &&
          element.renderObject is RenderParagraph) {
        labels.add(
          (element.renderObject as RenderParagraph).text.toPlainText(),
        );
      }
      element.visitChildElements(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    return jsonEncode({
      'stage': data.stage,
      'current': data.scores['p0'],
      'panels': panels,
      'labels': labels,
    });
  }).toJS;
  runApp(HistoricalMatchApp(data: data));
}
