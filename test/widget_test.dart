import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/main.dart';
import 'package:spend_utilizer/models/models.dart';
import 'package:spend_utilizer/services/chat_engine.dart';
import 'package:spend_utilizer/services/ocr_service.dart';
import 'package:spend_utilizer/services/share_inbox.dart';

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

  testWidgets('items shared from other apps are handled in the chat', (
    tester,
  ) async {
    final store = AppStore(storage: MemoryStorage());
    await store.load();
    final inbox = ShareInbox();
    await tester.pumpWidget(SpendUtilizerApp(store: store, shares: inbox));
    await tester.pumpAndSettle();

    // Open another tab first: a share should bring the chat back.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    // A bank SMS shared from the Messages app.
    inbox.add(
      const SharedItem.text(
        'Rs.250.00 debited from A/c XX1234 on 05-11-26 to VPA '
        'swiggy@axisbank (UPI Ref No 512345678901) -SBI',
      ),
    );
    await tester.pumpAndSettle();
    expect(store.txns.length, 1);
    expect(find.textContaining('Spent ₹250'), findsOneWidget);
    expect(inbox.hasPending, isFalse);

    // A shared Google Pay receipt (the phone's text reader is replaced by
    // the text it would return).
    store.setOwnership(store.accounts.single, Ownership.mine);
    OcrService.reader = (_) async => '''To Rohan Sen
₹235
Completed
5 Nov 2026, 9:56 pm
UPI transaction ID
667512345678
From: TEST USER (State Bank of India)
State Bank of India ••••1234
Google Pay''';
    inbox.add(const SharedItem.image('/tmp/receipt.jpg'));
    await tester.pumpAndSettle();
    expect(find.text('📷 Shared payment receipt'), findsOneWidget);
    expect(
      find.textContaining('Read from a Google Pay screenshot'),
      findsOneWidget,
    );
    await tester.tap(find.text(addShotOption));
    await tester.pumpAndSettle();
    expect(store.txns.length, 2);
    expect(store.txns.last.amount, 235);
    expect(store.txns.last.source, 'screenshot');
    expect(store.txns.last.accountId, store.accounts.single.id);

    // Reading errors are reported, not swallowed.
    OcrService.reader = (_) async => throw Exception('image unreadable');
    inbox.add(const SharedItem.image('/tmp/broken.jpg'));
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't read this image"), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
