import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:app/features/players/application/usecases/update_player_ranking_usecase.dart';
import 'package:app/features/players/presentation/widgets/edit_player_ranking_dialog.dart';

class MockUpdatePlayerRankingUseCase extends Mock
    implements UpdatePlayerRankingUseCase {}

void main() {
  late MockUpdatePlayerRankingUseCase mockUseCase;

  setUp(() {
    mockUseCase = MockUpdatePlayerRankingUseCase();
    when(
      () => mockUseCase.execute(
        playerId: any(named: 'playerId'),
        newRanking: any(named: 'newRanking'),
      ),
    ).thenAnswer((_) async {});
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updatePlayerRankingUseCaseProvider.overrideWithValue(mockUseCase),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (context) => const EditPlayerRankingDialog(
                      playerId: 'player-1',
                      currentRanking: 42.5,
                    ),
                  ),
                  child: const Text('Open dialog'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
  }

  TextField rankingField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  group('EditPlayerRankingDialog', () {
    testWidgets('shows current ranking in the text field and slider', (
      tester,
    ) async {
      await pumpDialog(tester);

      expect(rankingField(tester).controller!.text, '42.50');
      expect(find.text('Ranking: 42.50'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 42.5);
    });

    testWidgets('submits the typed ranking value', (tester) async {
      await pumpDialog(tester);

      await tester.enterText(find.byType(TextField), '77.5');
      await tester.pump();
      expect(find.text('Ranking: 77.50'), findsOneWidget);

      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      verify(
        () => mockUseCase.execute(playerId: 'player-1', newRanking: 77.5),
      ).called(1);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('clamps typed value above 100', (tester) async {
      await pumpDialog(tester);

      await tester.enterText(find.byType(TextField), '150');
      await tester.pump();

      expect(rankingField(tester).controller!.text, '100.00');
      expect(find.text('Ranking: 100.00'), findsOneWidget);

      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      verify(
        () => mockUseCase.execute(playerId: 'player-1', newRanking: 100.0),
      ).called(1);
    });

    testWidgets('accepts comma as decimal separator', (tester) async {
      await pumpDialog(tester);

      await tester.enterText(find.byType(TextField), '33,5');
      await tester.pump();

      expect(find.text('Ranking: 33.50'), findsOneWidget);

      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      verify(
        () => mockUseCase.execute(playerId: 'player-1', newRanking: 33.5),
      ).called(1);
    });

    testWidgets('moving the slider updates the text field', (tester) async {
      await pumpDialog(tester);

      await tester.drag(find.byType(Slider), const Offset(-100, 0));
      await tester.pump();

      final textValue = double.parse(rankingField(tester).controller!.text);
      expect(textValue, lessThan(42.5));
      expect(tester.widget<Slider>(find.byType(Slider)).value, textValue);
      expect(
        find.text('Ranking: ${textValue.toStringAsFixed(2)}'),
        findsOneWidget,
      );
    });

    testWidgets('shows error and does not submit invalid input', (
      tester,
    ) async {
      await pumpDialog(tester);

      await tester.enterText(find.byType(TextField), '12..3');
      await tester.pump();

      await tester.tap(find.text('Zapisz'));
      await tester.pump();

      expect(find.text('Wprowadź poprawny ranking (0-100).'), findsOneWidget);
      verifyNever(
        () => mockUseCase.execute(
          playerId: any(named: 'playerId'),
          newRanking: any(named: 'newRanking'),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
