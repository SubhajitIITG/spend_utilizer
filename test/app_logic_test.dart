import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/models/models.dart';
import 'package:spend_utilizer/services/chat_engine.dart';
import 'package:spend_utilizer/services/excel_export.dart';
import 'package:spend_utilizer/util/period.dart';
import 'package:spend_utilizer/services/sms_parser.dart';
import 'package:spend_utilizer/util/format.dart';

const hdfcCard1 =
    'Spent Rs.500 On HDFC Bank Credit Card xx1111 At SWIGGY '
    'On 2026-11-04:10:00:00 Avl Lmt Rs.50,000';
const hdfcCard2 =
    'Spent Rs.900 On HDFC Bank Credit Card xx2222 At AMAZON '
    'On 2026-11-04:11:00:00 Avl Lmt Rs.90,000';
const hdfcCard3 =
    'Spent Rs.300 On HDFC Bank Credit Card xx3333 At UBER '
    'On 2026-11-04:12:00:00 Avl Lmt Rs.30,000';
const sbiSavings =
    'Rs.200.00 debited from A/c XX4567 on 05-11-26 to VPA '
    'blinkit@axisbank (UPI Ref No 512345678901) -SBI';

Future<AppStore> newStore() async {
  final s = AppStore(storage: MemoryStorage());
  await s.load();
  return s;
}

void main() {
  test('three credit cards from one bank become three accounts', () async {
    final s = await newStore();
    for (final m in [hdfcCard1, hdfcCard2, hdfcCard3, sbiSavings]) {
      expect(s.addFromSms(m).status, SmsStatus.added);
    }
    expect(s.accounts.length, 4);
    // New accounts wait for "is this yours?" before they count.
    expect(s.pendingAccounts.length, 4);
    expect(s.banks, isEmpty);
    for (final a in s.pendingAccounts) {
      s.setOwnership(a, Ownership.mine);
    }
    expect(s.banks, ['HDFC', 'SBI']);
    expect(s.cardCount, 3);
    expect(s.bankAccountCount, 1);
    // Another spend on card 1 reuses the same account.
    s.addFromSms(hdfcCard1.replaceAll('SWIGGY', 'ZOMATO'));
    expect(s.accounts.length, 4);
  });

  test('duplicate SMS is not added twice', () async {
    final s = await newStore();
    expect(s.addFromSms(sbiSavings).status, SmsStatus.added);
    expect(s.addFromSms(sbiSavings).status, SmsStatus.duplicate);
    expect(s.txns.length, 1);
  });

  test('renamed account keeps matching new messages', () async {
    final s = await newStore();
    s.addFromSms(hdfcCard1);
    s.updateAccount(s.accounts.first, nickname: 'HDFC Millennia');
    final r = s.addFromSms(hdfcCard1.replaceAll('500', '650'));
    expect(r.account!.displayName, 'HDFC Millennia');
  });

  test('data survives save and reload', () async {
    final storage = MemoryStorage();
    final s = AppStore(storage: storage);
    await s.load();
    s.addFromSms(sbiSavings);
    await s.saveNow();
    final s2 = AppStore(storage: storage);
    await s2.load();
    expect(s2.txns.single.amount, 200);
    expect(s2.accounts.single.last4, '4567');
  });

  test('manual debit flow asks amount, category, account, note', () async {
    final s = await newStore();
    s.addFromSms(sbiSavings);
    final e = ChatEngine(s);
    e.start(ChatFlow.debit);
    expect(e.inputKind, InputKind.amount);
    expect(e.handle('abc').single.text, contains('valid amount'));
    e.handle('1,250');
    expect(e.inputKind, InputKind.date);
    expect(e.handle('25-12-2099').single.text, contains('future'));
    expect(e.handle('31-02-2026').single.text, contains('couldn'));
    e.handle('3-11-2026');
    expect(e.options, contains('🛒 Groceries'));
    e.handle('🛒 Groceries');
    expect(e.options, contains('SBI Bank Account ••4567'));
    e.handle('SBI Bank Account ••4567');
    final done = e.handle('Skip');
    expect(e.active, isFalse);
    final t = s.txnById(done.single.txnId)!;
    expect(t.type, TxnType.debit);
    expect(t.amount, 1250);
    expect(t.category, 'Groceries');
    expect(t.accountId, s.accounts.first.id);
    expect(t.date, DateTime(2026, 11, 3, 12));
  });

  test('credit flow offers refund category', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    e.start(ChatFlow.credit);
    e.handle('499');
    e.handle('Yesterday');
    expect(e.options, contains('↩️ Refund'));
    e.handle('↩️ Refund');
    e.handle('Cash');
    final done = e.handle('Skip');
    final t = s.txnById(done.single.txnId)!;
    expect(t.category, 'Refund');
    final y = DateTime.now().subtract(const Duration(days: 1));
    expect([t.date.year, t.date.month, t.date.day], [y.year, y.month, y.day]);
    expect(s.accountById(t.accountId)!.type, AccountType.cash);
  });

  test('lend and borrow track people and create reminders', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    e.start(ChatFlow.lend);
    e.handle('Rahul');
    e.handle('2000');
    e.handle('Today');
    e.handle('Skip');
    e.handle('In 1 week');
    e.handle('Skip');
    e.start(ChatFlow.borrow);
    e.handle('Priya');
    e.handle('500');
    e.handle('5 Nov');
    e.handle('Skip');
    e.handle('No reminder');
    e.handle('Skip');

    expect(s.totalToReceive, 2000);
    expect(s.totalToPay, 500);
    expect(s.reminders.single.title, contains('Rahul'));
    final borrow = s.txns.firstWhere((t) => t.type == TxnType.borrow);
    expect([borrow.date.month, borrow.date.day], [11, 5]);

    final lend = s.txns.firstWhere((t) => t.type == TxnType.lend);
    s.setSettled(lend, true);
    expect(s.totalToReceive, 0);
    expect(s.reminders.single.done, isTrue);
  });

  test('cancel stops a flow', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    e.start(ChatFlow.debit);
    e.handle(cancelOption);
    expect(e.active, isFalse);
    expect(s.txns, isEmpty);
  });

  test('pasting several messages at once adds each', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    final replies = e.handle('$hdfcCard1\n\n$hdfcCard2\n\nhello');
    expect(s.txns.length, 2);
    final summary = replies.firstWhere((r) => r.text.contains('added'));
    expect(summary.text, contains('2 added'));
    expect(summary.text, contains('1 not understood'));
  });

  test('SMS without a date says today was used', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    final r = e.handle('Rs 75 debited from A/c XX1234 to VPA chai@ybl');
    expect(r.first.text, contains('No date in the message'));
    expect(r.first.text, contains('📅'));
  });

  test('typed dates are understood', () {
    final now = DateTime(2026, 11, 8);
    expect(parseUserDate('5-11-2026', now: now), DateTime(2026, 11, 5));
    expect(parseUserDate('5/11', now: now), DateTime(2026, 11, 5));
    expect(parseUserDate('5 nov', now: now), DateTime(2026, 11, 5));
    expect(parseUserDate('5th November 26', now: now), DateTime(2026, 11, 5));
    expect(parseUserDate('yesterday', now: now), DateTime(2026, 11, 7));
    expect(parseUserDate('2026-11-01', now: now), DateTime(2026, 11, 1));
    expect(parseUserDate('31-02-2026', now: now), isNull);
    expect(parseUserDate('hello', now: now), isNull);
  });

  test('excel export has all sheets and rows', () async {
    final s = await newStore();
    s.addFromSms(hdfcCard1);
    s.addFromSms(sbiSavings);
    final bytes = ExcelExporter.build(s, Period.allTime(DateTime.now()));
    final x = Excel.decodeBytes(bytes);
    expect(
      x.tables.keys,
      containsAll([
        'Transactions',
        'Monthly Summary',
        'Category Summary',
        'Accounts',
        'Lend & Borrow',
        'Reminders',
      ]),
    );
    expect(x.tables.keys, isNot(contains('Sheet1')));
    final rows = x.tables['Transactions']!.rows;
    expect(rows.first.first!.value.toString(), 'Date');
    expect(rows.length, greaterThanOrEqualTo(3));
  });

  test('bot asks whether a new account is yours', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    final r = e.handle(hdfcCard1);
    expect(r.length, 2);
    expect(r.last.text, contains('HDFC Credit Card ••1111'));
    expect(e.flow, ChatFlow.ownership);
    expect(e.options, containsAll([mineOption, notMineOption]));
    final ok = e.handle(mineOption);
    expect(ok.first.text, contains('Added'));
    expect(s.accounts.single.isMine, isTrue);
    expect(s.cardCount, 1);
    // Same card again: no new question.
    expect(e.handle(hdfcCard1.replaceAll('SWIGGY', 'ZOMATO')).length, 1);
  });

  test('"not mine" turns the account into a payee', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    e.handle(
      'Rs.5,000.00 transferred from A/c XX7777 on 05-11-26 via IMPS '
      'Ref 612345678901 -SBI',
    );
    expect(e.flow, ChatFlow.ownership);
    e.handle(notMineOption);
    final acc = s.accounts.single;
    expect(acc.ownership, Ownership.notMine);
    expect(s.myAccounts, isEmpty);
    expect(s.banks, isEmpty);
    final t = s.txns.single;
    expect(t.accountId, isNull);
    expect(t.counterparty, 'A/c ••7777');
    expect(t.category, 'Payees');
    // Later messages about that account aren't attached to it either.
    e.handle(
      'Rs.100.00 transferred from A/c XX7777 on 06-11-26 via IMPS '
      'Ref 612345678902 -SBI',
    );
    expect(s.txns.last.accountId, isNull);
    expect(e.active, isFalse);
  });

  test('ownership question resumes after a restart', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    for (final m in e.handle(hdfcCard1)) {
      s.addChat(m);
    }
    final fresh = ChatEngine(s)..resumePendingQuestion();
    expect(fresh.flow, ChatFlow.ownership);
    fresh.handle('yes');
    expect(s.accounts.single.isMine, isTrue);
  });

  test('old data: debit "Transfer" becomes "Payees", cash is mine', () async {
    final old = MemoryStorage(
      '{"accounts":[{"id":"c","bank":"Cash","type":"cash","last4":""},'
      '{"id":"h","bank":"HDFC","type":"creditCard","last4":"1111"}],'
      '"txns":[{"id":"t","type":"debit","amount":5,"category":"Transfer",'
      '"date":"2026-11-01T12:00:00.000"}]}',
    );
    final s = AppStore(storage: old);
    await s.load();
    expect(s.txns.single.category, 'Payees');
    expect(s.accountById('c')!.isMine, isTrue);
    expect(s.accountById('h')!.ownership, Ownership.pending);
  });

  group('SIP & Mutual Funds', () {
    const sips = [
      'Rs.5,000.00 debited from A/c XX1234 on 05-11-26 ACH D- BSE LIMITED '
          '-SBI',
      'Your A/c XX1234 debited for INR 2,000 on 05-11-26 towards NACH Dr '
          'ICCL ZERODHA COIN. -HDFC',
      'Rs 1,500 debited from A/c XX1234 on 05-11-26 for SIP in Parag Parikh '
          'Flexi Cap Fund. -Axis',
      'INR 3,000 debited from A/c XX1234 on 05-11-26 to VPA groww.mf@yesbank '
          '(UPI Ref No 612345600001) -ICICI',
      'Rs.2,500 debited from a/c XX1234 on 05-11-26 HDFC Mutual Fund '
          'auto debit -SBI',
    ];

    test('SIP debits are recognised', () {
      for (final sms in sips) {
        expect(
          SmsParser.parse(sms)!.category,
          'SIP & Mutual Funds',
          reason: sms,
        );
      }
      // An ordinary EMI auto-debit stays an EMI.
      expect(
        SmsParser.parse(
          'Rs.8,000 debited from A/c XX1234 on 05-11-26 '
          'NACH Dr BAJAJ FINSERV EMI -SBI',
        )!.category,
        'EMI & Loans',
      );
    });

    test('SIPs count as Invested, not Spent', () async {
      final s = await newStore();
      for (final sms in sips) {
        s.addFromSms(sms);
      }
      s.addFromSms(
        'Rs.500 debited from A/c XX1234 on 05-11-26 to VPA '
        'swiggy@axisbank (UPI Ref No 512345678999) -SBI',
      );
      s.addFromSms(
        'Your A/c XX1234 is credited with Rs.50,000 on 01-11-26 '
        'by NEFT-SAL ACME -SBI',
      );
      final nov = DateTime(2026, 11);
      expect(s.spentIn(nov), 500);
      expect(s.investedIn(nov), 14000);
      expect(s.sipsInYear(2026).length, 5);
      expect(s.sipsInYear(2026).map(s.sipFundName).toSet(), {
        'BSE StAR MF',
        'Zerodha Coin',
        'Parag Parikh MF',
        'Groww',
        'HDFC MF',
      });
      // Per-account "spent" leaves SIPs out too.
      expect(s.accountSpentIn(s.accounts.first, nov), 500);
      expect(s.categoryTotals(nov, TxnType.debit).map((c) => c.category), [
        'Food & Dining',
      ]);
    });
  });

  group('FD, RD, stocks and bonds', () {
    const samples = {
      'Rs.50,000.00 debited from A/c XX1234 on 05-11-26 towards Fixed '
              'Deposit booking FD No 1234567. -SBI':
          'Fixed Deposit',
      'INR 1,00,000 debited from A/c XX1234 on 05-11-26 for new FD opened '
              'online. -HDFC':
          'Fixed Deposit',
      'Rs 2,000 debited from A/c XX1234 on 05-11-26 towards RD instalment '
              'RD A/c XX9876. -SBI':
          'Recurring Deposit',
      'Rs.25,000 debited from A/c XX1234 on 05-11-26 to ZERODHA BROKING '
              'LTD funds transfer -ICICI':
          'Stocks',
      'Rs 10,000 debited from A/c XX1234 on 05-11-26 to VPA '
              'upstox@hdfcbank (UPI Ref No 612345600002) -SBI':
          'Stocks',
      'Rs.15,000 debited from A/c XX1234 on 05-11-26 for Sovereign Gold '
              'Bond SGB 2026-27 -SBI':
          'Gold & Silver',
      'Rs 20,000 debited from A/c XX1234 on 05-11-26 to RBI RETAIL DIRECT '
              'T-Bill purchase -HDFC':
          'Bonds',
      'Rs.5,000 debited from A/c XX1234 on 05-11-26 towards NPS '
              'contribution -SBI':
          'NPS',
      'Rs.3,000 debited from A/c XX1234 on 05-11-26 ACH D- BSE LIMITED '
              '-SBI':
          'SIP & Mutual Funds',
    };

    test('each investment type is recognised', () {
      samples.forEach((sms, category) {
        expect(SmsParser.parse(sms)!.category, category, reason: sms);
      });
      // Look-alikes stay where they belong.
      expect(
        SmsParser.parse(
          'Spent Rs.500 On HDFC Bank Credit Card xx1111 At '
          'BIGBASKET On 2026-11-04:10:00:00',
        )!.category,
        'Groceries',
      );
      expect(
        SmsParser.parse(
          'Rs.300 debited from A/c XX1234 on 03-11-26 '
          'to VPA cardshop@ybl (UPI Ref 612345600003) -SBI',
        )!.category,
        isNot('Recurring Deposit'),
      );
    });

    test('FD maturity is an investment return', () {
      expect(
        SmsParser.parse(
          'Your A/c XX1234 is credited with Rs.52,500 on '
          '05-11-26 towards FD closure on maturity -SBI',
        )!.category,
        'Investment Returns',
      );
    });

    test('all of them count as Invested, none as Spent', () async {
      final s = await newStore();
      for (final sms in samples.keys) {
        s.addFromSms(sms);
      }
      final nov = DateTime(2026, 11);
      expect(s.spentIn(nov), 0);
      expect(s.investedIn(nov), 230000);
      expect(s.investmentsInYear(2026).length, samples.length);
    });
  });
}
