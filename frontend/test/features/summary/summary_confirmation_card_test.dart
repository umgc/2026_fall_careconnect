import 'package:care_connect_app/features/summary/summary_confirmation_card.dart';
import 'package:care_connect_app/providers/confirmation_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockProvider extends Mock implements ConfirmationProvider {}

void main() {
  late _MockProvider provider;

  setUp(() {
    provider = _MockProvider();
    when(() => provider.confirmItem(any(), note: any(named: 'note')))
        .thenAnswer((_) async => true);
    when(() => provider.dismissItem(any(), note: any(named: 'note')))
        .thenAnswer((_) async => true);
  });

  Map<String, dynamic> summaryItem({
    int id = 1,
    String payload =
        '{"headline":"Took aspirin","type":"ACTION_ITEM","detail":"81mg daily"}',
  }) =>
      {
        'id': id,
        'sourceType': 'SUMMARY',
        'status': 'PENDING',
        'payload': payload,
      };

  Widget harness(Map<String, dynamic> item) => MaterialApp(
        home: Scaffold(
          body: SummaryConfirmationCard(item: item, provider: provider),
        ),
      );

  testWidgets('renders headline, type chip, and detail from payload',
      (tester) async {
    await tester.pumpWidget(harness(summaryItem()));

    expect(find.text('Took aspirin'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget); // typeLabel for ACTION_ITEM
    expect(find.textContaining('81mg'), findsOneWidget);
  });

  testWidgets('falls back gracefully on unreadable payload', (tester) async {
    await tester.pumpWidget(harness(summaryItem(payload: 'not json')));

    expect(find.text('Unreadable summary item'), findsOneWidget);
  });

  testWidgets('Confirm routes to provider.confirmItem with the item id',
      (tester) async {
    await tester.pumpWidget(harness(summaryItem(id: 42)));

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pump(); // let the async handler run

    verify(() => provider.confirmItem(42)).called(1);
    verifyNever(() => provider.dismissItem(any(), note: any(named: 'note')));
  });

  testWidgets('Dismiss prompts for a reason then routes to dismissItem',
      (tester) async {
    await tester.pumpWidget(harness(summaryItem(id: 7)));

    // Card button opens the dialog.
    await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Inaccurate side effect');
    // Dialog action button (FilledButton labelled Dismiss).
    await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
    await tester.pump();

    verify(() => provider.dismissItem(7, note: 'Inaccurate side effect'))
        .called(1);
  });

  testWidgets('cancelling the dismiss dialog calls nothing', (tester) async {
    await tester.pumpWidget(harness(summaryItem()));

    await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();

    verifyNever(() => provider.dismissItem(any(), note: any(named: 'note')));
  });

  testWidgets('shows an error snackbar when provider returns false',
      (tester) async {
    when(() => provider.confirmItem(any(), note: any(named: 'note')))
        .thenAnswer((_) async => false);

    await tester.pumpWidget(harness(summaryItem(id: 1)));
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pump(); // async completes
    await tester.pump(); // snackbar renders

    expect(find.textContaining('Could not confirm'), findsOneWidget);
  });
}
