// Capture real Flutter pages with fake providers; no browser or backend needed.
// flutter test --update-goldens --dart-define=F014_FRAME_DIR=/absolute/output \
//   --dart-define=F014_SDK=/path/to/flutter --concurrency=1 tool/shared_rows_frames_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import '../test/fixtures/player_lists_app.dart';
import '../test/fixtures/shared_rows_app.dart';

void main() {
  const directory = String.fromEnvironment('F014_FRAME_DIR');
  setUpAll(() async {
    if (directory.isEmpty) {
      throw StateError('Set F014_FRAME_DIR to an absolute path');
    }
    const sdk = String.fromEnvironment('F014_SDK');
    if (sdk.isEmpty) {
      throw StateError('Set F014_SDK to the Flutter SDK root');
    }
    final roboto = File(
      '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    // Flutter tests use Ahem blocks for unspecified font families. Use the
    // Android default font for that fallback, without changing any page theme.
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(roboto.readAsBytes().then(ByteData.sublistView))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      await (FontLoader(
        '${family}_regular',
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
    }
  });
  for (final width in [360.0, 1440.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final page in ['selection', 'players', 'match', 'results']) {
        testWidgets('$page $width at $scale RootShell frame', (tester) async {
          tester.view.physicalSize = Size(width, width == 360 ? 640 : 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const frame = ValueKey('frame');
          await tester.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: page == 'selection' || page == 'players'
                  ? SharedRowsFixture(page: page, textScale: scale)
                  : PlayerListsFixture(page: page, textScale: scale),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final prefix = '$directory/$page-${width.toInt()}-$scale';
          await expectLater(
            find.byKey(frame),
            matchesGoldenFile('$prefix.png'),
          );
          if (page == 'selection') {
            await tester.ensureVisible(find.text('Gracz 100'));
            await tester.pumpAndSettle();
            expect(find.text('Gracz 100').hitTestable(), findsOneWidget);
            await expectLater(
              find.byKey(frame),
              matchesGoldenFile('$prefix-bottom.png'),
            );
            await tester.enterText(find.byType(TextField), 'Anna');
            await tester.pumpAndSettle();
            await expectLater(
              find.byKey(frame),
              matchesGoldenFile('$prefix-search.png'),
            );
          }
        });
      }
    }
  }
}
