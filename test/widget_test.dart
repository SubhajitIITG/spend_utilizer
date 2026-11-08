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
      'On 2026-11-04:12:30:45 Avl Lmt Rs.85,000',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(store.txns.length, 1);
    expect(find.textContaining('Spent ₹1,250.50 at BIGBASKET'), findsOneWidget);
    expect(
      find.textContaining('Is this your own credit card?'),
      findsOneWidget,
    );
    await tester.tap(find.text('✅ Yes, it\'s mine'));
    await tester.pumpAndSettle();
    expect(store.accounts.single.isMine, isTrue);

    // Start a manual debit flow from the quick actions.
    await tester.tap(find.text('Debit'));
    await tester.pumpAndSettle();
    expect(find.text('How much did you spend? 💸'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '120');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('When did you spend it? 📅'), findsOneWidget);
    expect(find.text('Pick date'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);

    // Dashboard renders.
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Total spent'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Your banks & cards'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Your banks & cards'), findsOneWidget);
    expect(find.text('🏦 1 banks'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // flush save timer
  });

  testWidgets('clear chat keeps transactions', (tester) async {
    final store = AppStore(storage: MemoryStorage());
    await store.load();
    await tester.pumpWidget(SpendUtilizerApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Clear chat'), findsNothing); // nothing to clear yet

    await tester.enterText(
      find.byType(TextField).last,
      'Rs.250.00 debited from A/c XX1234 on 05-11-26 to VPA '
      'swiggy@axisbank (UPI Ref No 512345678901) -SBI',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('✅ Yes, it\'s mine'));
    await tester.pumpAndSettle();
    expect(store.chat, isNotEmpty);

    // Typed command opens the same confirmation; cancel keeps the chat.
    await tester.enterText(find.byType(TextField).last, 'clear chat');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Clear chat history?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.chat, isNotEmpty);

    // Chip → confirm.
    await tester.tap(find.text('Clear chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear chat'));
    await tester.pumpAndSettle();
    expect(store.chat, isEmpty);
    expect(store.txns.length, 1);
    expect(find.text('Track every rupee by chatting'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
