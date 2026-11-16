// SYNTHETIC browser entrypoint. Never imported by lib/main.dart.
import 'dart:convert';
import 'dart:js_interop';
import 'package:app/features/matches/presentation/widgets/match_level_panel.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import '../test/fixtures/match_level_app.dart';

@JS('matchLevelMetrics')
external set _metrics(JSFunction callback);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  SemanticsBinding.instance.ensureSemantics();
  final query = Uri.base.queryParameters;
  final data = MatchLevelData(
    completed: int.tryParse(query['completed'] ?? '') ?? 26,
    configured: query['configured'] != 'false',
    role: query['guest'] == 'true' ? null : SquadRole.owner,
  )..failLoad = query['failLoad'] == 'true'
   ..failSave = query['failSave'] == 'true';
  _metrics = (() {
    final labels = <String>[];
    final ratings = <double>[];
    final fields = <Object?>[];
    void visit(Element e) {
      if (e.widget case final MatchLevelRating rating) { ratings.add(rating.rating); }
      if (e.widget case final TextField field) {
        final box = e.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final p = box.localToGlobal(Offset.zero);
          fields.add({'label':field.decoration?.labelText,'text':field.controller?.text,'x':p.dx+box.size.width/2,'y':p.dy+box.size.height/2});
        }
      }
      if (e is RenderObjectElement && e.renderObject is RenderParagraph) {
        labels.add((e.renderObject as RenderParagraph).text.toPlainText());
      }
      e.visitChildElements(visit);
    }
    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    return jsonEncode({'labels':labels,'ratings':ratings,'fields':fields,'saves':data.saves,'thresholds':data.thresholds,'requests':data.requests});
  }).toJS;
  runApp(MatchLevelApp(data:data,screen:query['screen']??'list'));
}
