// Synthetic RootShell fixture with read-only render/glyph diagnostics.
import 'dart:convert';
import 'dart:js_interop';

import 'package:app/core/widgets/probability_slider.dart';
import 'package:app/features/matches/presentation/widgets/match_view_roster.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../test/fixtures/lineup_app.dart';

@JS('matchViewMetrics')
external set _metrics(JSFunction callback);

List<double> _rect(RenderBox box, [Rect? local]) {
  final rect = local ?? Offset.zero & box.size;
  final origin = box.localToGlobal(rect.topLeft);
  return [origin.dx, origin.dy, rect.width, rect.height];
}

Map<String, Object?> _paragraph(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  return {
    'text': text,
    'rect': _rect(paragraph),
    'maxLines': paragraph.maxLines,
    'exceeded': paragraph.didExceedMaxLines,
    'glyphs': [
      for (var index = 0; index < text.length; index++)
        if (text[index].trim().isNotEmpty)
          {
            'index': index,
            'char': text[index],
            'boxes': [
              for (final box in paragraph.getBoxesForSelection(
                TextSelection(baseOffset: index, extentOffset: index + 1),
              ))
                _rect(paragraph, box.toRect()),
            ],
          },
    ],
  };
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  SemanticsBinding.instance.ensureSemantics();
  final errors = <String>[];
  FlutterError.onError = (details) {
    errors.add(details.toString());
    FlutterError.presentError(details);
  };
  _metrics = (() {
    final panels = <Object?>[];
    final identities = <String, Object?>{};
    Object? footer;
    Object? viewport;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is MatchViewPlayerPanel) {
        final texts = <Object?>[];
        void paragraphs(Element child) {
          if (child.renderObject case final RenderParagraph paragraph) {
            if (child is RenderObjectElement) texts.add(_paragraph(paragraph));
          }
          child.visitChildElements(paragraphs);
        }

        element.visitChildElements(paragraphs);
        panels.add({
          'id': widget.player.playerId,
          'name': widget.player.name,
          'ranking': widget.player.ranking.toStringAsFixed(2),
          'rect': _rect(element.renderObject! as RenderBox),
          'texts': texts,
        });
      }
      if (widget is ProbabilitySlider) {
        footer = _rect(element.renderObject! as RenderBox);
      }
      if (widget is CustomScrollView) {
        viewport = _rect(element.renderObject! as RenderBox);
      }
      if (widget.key case final ValueKey<String> key) {
        if (key.value.startsWith('lineup-')) {
          identities[key.value] = _rect(element.renderObject! as RenderBox);
        }
      }
      element.visitChildElements(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    return jsonEncode({
      'panels': panels,
      'identities': identities,
      'footer': footer,
      'viewport': viewport,
      'errors': errors,
    }).toJS;
  }).toJS;
  final params = Uri.base.queryParameters;
  runApp(
    lineupFixture(
      count: int.tryParse(params['count'] ?? '') ?? 8,
      awayCount: int.tryParse(params['away'] ?? ''),
      scale: double.tryParse(params['scale'] ?? '') ?? 1,
      longNames: params['long'] != 'false',
      wideRankings: true,
      savedScore: params['saved'] != 'false',
      role: params['reader'] == 'true' ? SquadRole.member : SquadRole.owner,
    ),
  );
}
