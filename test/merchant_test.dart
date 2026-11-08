import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/models/models.dart';
import 'package:spend_utilizer/services/chat_engine.dart';
import 'package:spend_utilizer/services/sync_service.dart';

import 'sync_test.dart' show FakeCloud;

/// A UPI payment to a small stall the parser can't categorise.
String stall(int amount, int daysAgo, {String vpa = 'raju.k1987@okaxis'}) {
  final d = DateTime.now().subtract(Duration(days: daysAgo));
  final date =
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}'
      '-${d.year % 100}';
  return 'Rs.$amount.00 debited from A/c XX4567 on $date to VPA $vpa '
      '(UPI Ref No 5${amount}0$daysAgo${vpa.length}12345) -SBI';
}

Future<AppStore> newStore() async {
  final s = AppStore(storage: MemoryStorage());
  await s.load();
  // The account these payments come from is already confirmed as the
  // user's, so the bot only asks about merchants.
  s.addAccount(
    Account(id: 'sbi', bank: 'SBI', type: AccountType.savings, last4: '4567'),
  );
  return s;
}

void main() {
  test(
    'three small payments to an unknown merchant trigger a question',
    () async {
      final s = await newStore();
      final e = ChatEngine(s);
      expect(e.handle(stall(20, 3)).length, 1);
      expect(e.handle(stall(25, 2)).length, 1);
      expect(s.merchantsToReview(), isEmpty);

      final replies = e.handle(stall(30, 1));
      expect(replies.length, 2);
      expect(replies.last.text, contains('raju.k1987@okaxis'));
      expect(replies.last.text, contains('3 times'));
      expect(replies.last.text, contains('₹20–₹30 each'));
      expect(e.flow, ChatFlow.merchant);
      expect(e.options.first, personOption);
      expect(e.options, contains('🍔 Food & Dining'));
      expect(e.options, containsAll([askLaterOption, neverAskOption]));
    },
  );

  test('answering recategorises past and future payments', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    for (var i = 3; i >= 1; i--) {
      e.handle(stall(20 + i, i));
    }
    e.handle('🍔 Food & Dining');
    expect(e.inputHint, contains('Raju Tea Stall'));
    final done = e.handle('Raju Tea Stall');
    expect(done.first.text, contains('updated 3 payments'));
    expect(e.active, isFalse);

    expect(s.txns.every((t) => t.category == 'Food & Dining'), isTrue);
    expect(s.merchantLabel('raju.k1987@okaxis'), 'Raju Tea Stall');
    expect(s.merchantsToReview(), isEmpty);

    // Future payment is categorised automatically and shows the name.
    final r = e.handle(stall(22, 0));
    expect(s.txns.last.category, 'Food & Dining');
    expect(r.single.text, contains('Raju Tea Stall'));
  });

  test('marking as a friend uses Friends & Family', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    for (var i = 4; i >= 1; i--) {
      e.handle(stall(100, i, vpa: '9876543210@ybl'));
    }
    e.handle(personOption);
    expect(e.inputHint, isNotEmpty);
    e.handle('Amit');
    expect(s.txns.length, 4); // 4th paste during the question still counts
    expect(s.txns.every((t) => t.category == 'Friends & Family'), isTrue);
    expect(s.merchantRule('9876543210@ybl')!.isPerson, isTrue);
    expect(s.merchantLabel('9876543210@ybl'), 'Amit');
  });

  test('"Don\'t ask again" and "Ask me later" stop the question', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    for (var i = 3; i >= 1; i--) {
      e.handle(stall(20 + i, i));
    }
    e.handle(neverAskOption);
    expect(e.active, isFalse);
    expect(e.handle(stall(40, 0)).length, 1); // no new question
    expect(s.merchantsToReview(), isEmpty);

    for (var i = 3; i >= 1; i--) {
      e.handle(stall(50 + i, i, vpa: 'kumar.st@ybl'));
    }
    expect(e.flow, ChatFlow.merchant);
    e.handle(askLaterOption);
    expect(s.merchantsToReview(), isEmpty);
    expect(
      s.merchantsToReview(now: DateTime.now().add(const Duration(days: 8))),
      isNotEmpty,
    );
  });

  test(
    'big, rare or already-categorised payments are not asked about',
    () async {
      final s = await newStore();
      final e = ChatEngine(s);
      // Large amounts (rent-like).
      for (var i = 3; i >= 1; i--) {
        e.handle(stall(15000 + i, i, vpa: 'landlord@ybl'));
      }
      // Only twice.
      e.handle(stall(30, 2, vpa: 'rare@ybl'));
      e.handle(stall(31, 1, vpa: 'rare@ybl'));
      // Known merchant (Swiggy → Food & Dining by keywords).
      for (var i = 3; i >= 1; i--) {
        e.handle(stall(200 + i, i, vpa: 'swiggy.order@axisbank'));
      }
      // Older than 30 days.
      for (var i = 3; i >= 1; i--) {
        e.handle(stall(20 + i, 40 + i, vpa: 'old@ybl'));
      }
      expect(s.merchantsToReview(), isEmpty);
      expect(e.active, isFalse);
    },
  );

  test('changing a category by hand teaches the merchant', () async {
    final s = await newStore();
    s.addFromSms(stall(20, 3));
    s.addFromSms(stall(21, 2));
    final first = s.txns.first;
    final others = s.recategorize(first, 'Groceries');
    expect(others, 1);
    expect(first.userCategorized, isTrue);
    s.addFromSms(stall(22, 1));
    expect(s.txns.last.category, 'Groceries');

    // A later rule never overrides a hand-picked category.
    s.setMerchantCategory('raju.k1987@okaxis', 'Food & Dining');
    expect(first.category, 'Groceries');
    expect(s.txns.last.category, 'Food & Dining');
  });

  test('cancel snoozes the question until tomorrow', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    for (var i = 3; i >= 1; i--) {
      e.handle(stall(20 + i, i));
    }
    e.handle(cancelOption);
    expect(e.handle(stall(40, 0)).length, 1);
    expect(
      s.merchantsToReview(now: DateTime.now().add(const Duration(days: 2))),
      isNotEmpty,
    );
  });

  test('an open question is picked up again after a restart', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    for (var i = 3; i >= 1; i--) {
      for (final m in e.handle(stall(20 + i, i))) {
        s.addChat(m);
      }
    }
    expect(e.flow, ChatFlow.merchant);
    final fresh = ChatEngine(s)..resumePendingQuestion();
    expect(fresh.flow, ChatFlow.merchant);
    fresh.handle('🛒 Groceries');
    fresh.handle(skipOption);
    expect(s.txns.every((t) => t.category == 'Groceries'), isTrue);
    // Nothing to resume once answered.
    expect((ChatEngine(s)..resumePendingQuestion()).active, isFalse);
  });

  test('merchant knowledge syncs to other devices', () async {
    final cloud = FakeCloud();
    final a = await newStore();
    final b = await newStore();
    final sa = SyncService(a)..start(cloud, 'u1');
    final sb = SyncService(b)..start(cloud, 'u1');
    a.addFromSms(stall(20, 1));
    a.setMerchantCategory('raju.k1987@okaxis', 'Food & Dining', alias: 'Raju');
    await sa.syncNow();
    await sb.syncNow();
    expect(b.merchantLabel('raju.k1987@okaxis'), 'Raju');
    b.addFromSms(stall(25, 0));
    expect(b.txns.last.category, 'Food & Dining');
    sa.stop();
    sb.stop();
  });
}
