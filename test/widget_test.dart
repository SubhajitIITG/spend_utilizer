import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/main.dart';

void main() {
  testWidgets('pasting a bank SMS in chat records it', (tester) async {
    final store = AppStore(storage: MemoryStorage());
    await store.load();
    await tester.pumpWidget(SpendUtilizerApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Track every rupee by chatting'), findsOneWidget);

    await tester.enterText(
        find.byType(TextField).last,
        'Spent Rs.1,250.50 On HDFC Bank Credit Card xx4321 At BIGBASKET '
        'On 2026-11-04:12:30:45 Avl Lmt Rs.85,000');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(store.txns.length, 1);
    expect(find.textContaining('Spent ₹1,250.50 at BIGBASKET'), findsOneWidget);
    expect(find.textContaining('New credit card found'), findsOneWidget);

    // Start a manual debit flow from the quick actions.
    await tester.tap(find.text('Debit'));
    await tester.pumpAndSettle();
    expect(find.text('How much did you spend? 💸'), findsOneWidget);

    // Dashboard renders.
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Your banks & cards'), findsOneWidget);
    expect(find.text('🏦 1 banks'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // flush save timer
  });
}
