// Synthetic RootShell fixture with read-only render/glyph diagnostics.
import 'dart:convert';
import 'dart:js_interop';

import 'package:app/core/widgets/probability_slider.dart';
import 'package:app/core/widgets/lineup_header.dart';
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
  final painter =
      TextPainter(
        text: paragraph.text,
        textAlign: paragraph.textAlign,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        locale: paragraph.locale,
        strutStyle: paragraph.strutStyle,
        textWidthBasis: paragraph.textWidthBasis,
        textHeightBehavior: paragraph.textHeightBehavior,
      )..layout(
        minWidth: paragraph.constraints.minWidth,
        maxWidth: paragraph.constraints.maxWidth,
      );
  final natural = {
    'width': painter.width,
    'height': painter.height,
    'lines': painter.computeLineMetrics().length,
  };
  painter.dispose();
  final ancestors = <Object?>[];
  for (
    RenderObject? parent = paragraph;
    parent != null;
    parent = parent.parent
  ) {
    if (parent is RenderBox) {
      ancestors.add({
        'type': parent.runtimeType.toString(),
        'constraints': parent.constraints.toString(),
        'size': [parent.size.width, parent.size.height],
        if (parent is RenderConstrainedBox)
          'additionalConstraints': parent.additionalConstraints.toString(),
      });
    }
    if (parent is RenderViewport) break;
  }
  return {
    'text': text,
    'natural': natural,
    'ancestors': ancestors,
    'style': {
      'fontFamily': paragraph.text.style?.fontFamily,
      'fontFamilyFallback': paragraph.text.style?.fontFamilyFallback,
      'fontWeight': paragraph.text.style?.fontWeight?.value,
      'height': paragraph.text.style?.height,
      'letterSpacing': paragraph.text.style?.letterSpacing,
      'wordSpacing': paragraph.text.style?.wordSpacing,
    },
    'locale': paragraph.locale.toString(),
    'textDirection': paragraph.textDirection.toString(),
    'textWidthBasis': paragraph.textWidthBasis.toString(),
    'textHeightBehavior': paragraph.textHeightBehavior.toString(),
    'rect': _rect(paragraph),
    'maxLines': paragraph.maxLines,
    'exceeded': paragraph.didExceedMaxLines,
    'fontSize': paragraph.text.style?.fontSize,
    'scaledFontSize': paragraph.textScaler.scale(
      paragraph.text.style?.fontSize ?? 14,
    ),
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
    final labels = <Object?>[];
    Object? teams;
    Object? footer;
    Object? viewport;
    Object? headerGeometry;
    void visit(Element element) {
      final widget = element.widget;
      if (element is RenderObjectElement &&
          element.renderObject is RenderParagraph) {
        final paragraph = element.renderObject as RenderParagraph;
        labels.add({
          'text': paragraph.text.toPlainText(),
          'rect': _rect(paragraph),
        });
      }
      if (widget is LineupHeader) {
        teams = {
          'home': {
            'name': widget.homeName,
            'color': widget.homeColor.toARGB32(),
          },
          'away': {
            'name': widget.awayName,
            'color': widget.awayColor.toARGB32(),
          },
        };
      }
      if (widget is SliverPersistentHeader &&
          element.renderObject is RenderSliverPersistentHeader) {
        final render = element.renderObject! as RenderSliverPersistentHeader;
        headerGeometry = {
          'minExtent': widget.delegate.minExtent,
          'maxExtent': widget.delegate.maxExtent,
          'scrollOffset': render.constraints.scrollOffset,
          'paintExtent': render.geometry?.paintExtent,
        };
      }
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
      'teams': teams,
      'labels': labels,
      'footer': footer,
      'viewport': viewport,
      'headerGeometry': headerGeometry,
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
      guest: params['guest'] == 'true',
      role: params['reader'] == 'true' ? SquadRole.member : SquadRole.owner,
    ),
  );
}
