import 'package:care_connect_app/features/summary/summary_confirmation_list.dart';
import 'package:care_connect_app/providers/confirmation_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockProvider extends Mock implements ConfirmationProvider {}

Map<String, dynamic> _item(int id, String sourceType, String headline) => {
      'id': id,
      'sourceType': sourceType,
      'status': 'PENDING',
      'payload': '{"headline":"$headline"}',
    };

void main() {
  late _MockProvider provider;

  setUp(() {
    provider = _MockProvider();
    when(() => provider.loadFromCache()).thenAnswer((_) async {});
    when(() => provider.fetchFromBackend(sourceType: any(named: 'sourceType')))
        .thenAnswer((_) async {});
  });

  // Plain Provider (not ChangeNotifierProvider) so we don't need a real Listenable;
  // each test sets pendingItems explicitly before pumping.
  Widget harness() => MaterialApp(
        home: Scaffold(
          body: Provider<ConfirmationProvider>.value(
            value: provider,
            child: const SummaryConfirmationList(),
          ),
        ),
      );

  testWidgets('shows empty state when no SUMMARY items are pending',
      (tester) async {
    when(() => provider.pendingItems).thenReturn([]);

    await tester.pumpWidget(harness());
    await tester.pump(); // run post-frame callback

    expect(find.text('No summary items to review'), findsOneWidget);
  });

  testWidgets('renders only SUMMARY items, filtering out other source types',
      (tester) async {
    when(() => provider.pendingItems).thenReturn([
      _item(1, 'SUMMARY', 'Took aspirin'),
      _item(2, 'ASK_AI', 'Unrelated ask-ai item'),
    ]);

    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Took aspirin'), findsOneWidget);
    expect(find.text('Unrelated ask-ai item'), findsNothing);
    expect(find.text('No summary items to review'), findsNothing);
  });

  testWidgets('syncs from backend with sourceType SUMMARY on mount',
      (tester) async {
    when(() => provider.pendingItems).thenReturn([]);

    await tester.pumpWidget(harness());
    await tester.pump();

    verify(() => provider.fetchFromBackend(sourceType: 'SUMMARY')).called(1);
  });
}
