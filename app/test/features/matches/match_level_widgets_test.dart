import 'package:app/features/matches/presentation/widgets/match_level_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../fixtures/match_level_app.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  Future<void> mount(WidgetTester tester, MatchLevelData data, String screen) async {
    tester.view.physicalSize = const Size(390,1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(data.dispose);
    await tester.pumpWidget(MatchLevelApp(data:data,screen:screen));
    await tester.pumpAndSettle();
  }
  testWidgets('list and details agree on accessible numeric historical level', (tester) async {
    final data = MatchLevelData();
    await mount(tester,data,'list');
    expect(find.text('3,5'),findsOneWidget);
    expect(find.bySemanticsLabel('Poziom meczu: 3,5 na 5'),findsOneWidget);
    await tester.tap(find.text('ZIELONI'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(MatchLevelRating),200);
    expect(find.text('3,5'),findsOneWidget);
    expect(find.textContaining('Siła obsady'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  for (final screen in ['list','details']) {
    testWidgets('$screen hidden at 25 completed matches', (tester) async {
      await mount(tester,MatchLevelData(completed:25),screen);
      expect(find.byType(MatchLevelRating),findsNothing);
      expect(find.text('Poziom meczu'),findsNothing);
    });
  }
  testWidgets('settings entry opens separate page, saves and rereads thresholds', (tester) async {
    final data=MatchLevelData();
    await mount(tester,data,'settings');
    expect(find.byType(TextField),findsNothing);
    await tester.scrollUntilVisible(find.text('Zmiana progów gwiazdek'),150);
    await tester.tap(find.text('Zmiana progów gwiazdek'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField),findsNWidgets(5));
    await tester.enterText(find.byType(TextField).at(0),'20');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Zapisz')).onPressed,isNull);
    await tester.enterText(find.byType(TextField).at(0),'12,5');
    await tester.pump();
    expect(find.text('1,5 ★: 16,25'),findsOneWidget);
    await tester.ensureVisible(find.text('Zapisz'));
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(data.thresholds!.first,12.5);
    expect(data.saves,1);
    expect(find.text('Zapisano progi gwiazdek.'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('failed load permits retry; failed save retains draft and reports failure', (tester) async {
    final data=MatchLevelData()..failLoad=true;
    await mount(tester,data,'stars');
    expect(find.text('Nie udało się wczytać progów.'),findsOneWidget);
    data.failLoad=false;
    await tester.tap(find.text('Spróbuj ponownie'));
    await tester.pumpAndSettle();
    data.failSave=true;
    await tester.enterText(find.byType(TextField).first,'12');
    await tester.ensureVisible(find.text('Zapisz'));
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(find.text('Nie udało się zapisać progów. Spróbuj ponownie.'),findsOneWidget);
    expect(data.saves,0);
    expect(data.thresholds!.first,10);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,'12');
  });
  for (final screen in ['settings','stars']) {
    testWidgets('guest cannot manage $screen', (tester) async {
      final data=MatchLevelData(role:null);
      await mount(tester,data,screen);
      expect(find.byType(TextField),findsNothing);
      expect(find.text('Zmiana progów gwiazdek'),findsNothing);
      expect(data.requests,isEmpty);
    });
  }
}
