// Browser-only proof instrumentation. Reads actual laid-out Flutter paragraphs.
import 'dart:convert';
import 'dart:js_interop';

import 'package:app/features/matches/presentation/widgets/match_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

@JS('matchListMetrics')
external set _metrics(JSFunction callback);

void installMatchListMetrics() {
  _metrics = (() => jsonEncode(_cards()).toJS).toJS;
}

List<Map<String, Object?>> _cards() {
  final cards = <Map<String, Object?>>[];
  void visit(Element element) {
    if (element.widget case final MatchTile tile) {
      final root = element.findRenderObject()! as RenderBox;
      final paragraphs = <Map<String, Object?>>[];
      void inspect(RenderObject object) {
        if (object is RenderParagraph) {
          final text = object.text.toPlainText();
          final origin = object.localToGlobal(Offset.zero);
          final unwrapped = TextPainter(
            text: object.text,
            textDirection: object.textDirection,
            textScaler: object.textScaler,
            locale: object.locale,
            strutStyle: object.strutStyle,
            textHeightBehavior: object.textHeightBehavior,
            textWidthBasis: object.textWidthBasis,
          )..layout();
          paragraphs.add({
            'text': text,
            'fontSize': object.text.style?.fontSize,
            'x': origin.dx,
            'y': origin.dy,
            'width': object.size.width,
            'height': object.size.height,
            'minIntrinsic': object.getMinIntrinsicWidth(double.infinity),
            'maxIntrinsic': object.getMaxIntrinsicWidth(double.infinity),
            'maxWidth': object.constraints.maxWidth.isFinite
                ? object.constraints.maxWidth
                : null,
            'exceededMaxLines': object.didExceedMaxLines,
            'unwrappedWidth': unwrapped.width,
            'unwrappedHeight': unwrapped.height,
            'glyphs': [
              for (var i = 0; i < text.length; i++)
                for (final box in object.getBoxesForSelection(
                  TextSelection(baseOffset: i, extentOffset: i + 1),
                ))
                  {
                    'character': text[i],
                    'left': box.left,
                    'right': box.right,
                    'top': box.top,
                    'bottom': box.bottom,
                  },
            ],
          });
          unwrapped.dispose();
        }
        object.visitChildren(inspect);
      }

      inspect(root);
      final origin = root.localToGlobal(Offset.zero);
      cards.add({
        'id': tile.match.matchId,
        'x': origin.dx,
        'y': origin.dy,
        'width': root.size.width,
        'height': root.size.height,
        'paragraphs': paragraphs,
      });
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return cards;
}
