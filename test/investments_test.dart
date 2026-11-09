import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/models/models.dart';
import 'package:spend_utilizer/services/categories.dart';
import 'package:spend_utilizer/services/chat_engine.dart';
import 'package:spend_utilizer/services/fund_orders_parser.dart';
import 'package:spend_utilizer/services/sms_parser.dart';

// Fund-house messages (folio digits changed).
const utiSip =
    'Dear Investor, Your SIP under folio XXXXXXXX1234 in scheme UTI Nifty 50 '
    'Index Fund Direct Plan Growth invested through (000000-0) direct for '
    'Rs.9000.00 is processed and 56.250 units at NAV 159.991 dated '
    '13-OCT-2026 are allotted on receipt of funds. Regards -UTI MF';
const axisSip =
    'Dear Investor, Payment of Rs. 1999.90 towards your SIP in Axis Small '
    'Cap Fund Direct Growth has been received and 14.950 units at NAV 133.77 '
    'are allotted in Folio XXXXXXXX4321. Axis MF';
const axisCancel =
    'Your request of SIP cancellation in Folio-XXXXXXXX5678 under Axis Small '
    'Cap Fund Direct Growth Dtd 11/09/2025 is processed and discontinued '
    'w.e.f. 21/07/2026. Axis MF';
const axisCancelAck =
    'Dear Investor, Acknowledge receipt of your SIP Cancellation request of '
    'Axis Small Cap Fund Direct Growth in folio XXXXXXXX5678. Axis MF';

// Groww → Orders → Mutual Funds, read row by row.
const growwRows = '''
08:23
All Orders
Stocks
F&O
Mutual Funds
US Stocks
06 Nov '26
ICICI Prudential Short Term Fund ...
₹50,000.00
One-time
In progress
09 Oct '26
Nippon India Small Cap Fund Dire...
₹2,000.00
SIP Installment
Completed
Axis Small Cap Fund Direct Growth
₹2,000.00
SIP Installment
Completed
UTI Nifty 50 Index Fund Direct Gr...
₹9,000.00
SIP Installment
Completed
SBI Contra Direct Plan Growth
₹1,000.00
SIP Installment
Completed
Parag Parikh Flexi Cap Fund Dire...
₹7,000.00
SIP Installment
Completed
08 Oct '26
Nippon India Pharma Fund Direct...
₹2,000.00
SIP Installment
Completed
''';

// The same screen read column by column, with ₹ misread as 7 once.
const growwColumns = '''
All Orders
Stocks F&O
Mutual Funds
US Stocks
06 Nov '26
ICICI Prudential Short Term Fund ...
One-time
09 Oct '26
Nippon India Small Cap Fund Dire...
SIP Installment
Axis Small Cap Fund Direct Growth
SIP Installment
UTI Nifty 50 Index Fund Direct Gr...
SIP Installment
SBI Contra Direct Plan Growth
SIP Installment
Parag Parikh Flexi Cap Fund Dire...
SIP Installment
08 Oct '26
Nippon India Pharma Fund Direct...
SIP Installment
₹50,000.00
• In progress
₹2,000.00
• Completed
72,000.00
• Completed
₹9,000.00
• Completed
₹1,000.00
• Completed
₹7,000.00
• Completed
₹2,000.00
• Completed
''';

Future<AppStore> newStore() async {
  final s = AppStore(storage: MemoryStorage());
  await s.load();
  return s;
}

void main() {
  final now = DateTime(2026, 11, 9, 10);

  group('fund house SMS', () {
    test('UTI SIP allotment', () {
      final p = SmsParser.parse(utiSip, now: now)!;
      expect(p.isFundSms, isTrue);
      expect(p.type, TxnType.debit);
      expect(p.amount, 9000);
      expect(p.category, sipCategory);
      expect(p.counterparty, 'UTI Nifty 50 Index Fund');
      expect(p.date.year, 2026);
      expect(p.date.month, 10);
      expect(p.date.day, 13);
      expect(p.note, contains('Folio ••1234'));
      expect(p.note, contains('56.250 units @ NAV 159.991'));
    });

    test('Axis "payment received" is an investment, not income', () {
      final p = SmsParser.parse(axisSip, now: now)!;
      expect(p.type, TxnType.debit);
      expect(p.amount, 1999.90);
      expect(p.category, sipCategory);
      expect(p.counterparty, 'Axis Small Cap Fund');
      expect(p.dateFound, isFalse);
    });

    test('cancellation notices are not transactions', () {
      expect(SmsParser.parse(axisCancel, now: now), isNull);
      expect(SmsParser.parse(axisCancelAck, now: now), isNull);
    });

    test('chat records it as invested and explains cancellations', () async {
      final s = await newStore();
      final e = ChatEngine(s);
      final r = e.handle(utiSip);
      expect(r.first.text, contains('Invested ₹9,000'));
      expect(r.first.text, contains('UTI Nifty 50 Index Fund'));
      expect(s.accounts, isEmpty); // no bank account guessed
      expect(s.txns.single.category, sipCategory);
      final c = e.handle(axisCancel);
      expect(c.single.text, contains('SIP cancellation'));
      expect(s.txns.length, 1);
    });

    test('bank auto-debit and fund SMS are one investment', () async {
      final s = await newStore();
      s.addFromSms(utiSip);
      final bank = s.addFromSms(
        'Rs.9000.00 debited from A/c XX4567 on 13-10-26 towards ACH D- '
        'BSE LIMITED. -SBI',
      );
      expect(bank.status, SmsStatus.duplicate);
      expect(s.txns.length, 1);
      expect(s.txns.single.accountId, isNotNull);
    });

    test('fund SMS after the bank debit names the fund', () async {
      final s = await newStore();
      s.addFromSms(
        'Rs.9000.00 debited from A/c XX4567 on 13-10-26 towards ACH D- '
        'BSE LIMITED. -SBI',
      );
      expect(s.txns.single.category, sipCategory);
      expect(s.addFromSms(utiSip).status, SmsStatus.duplicate);
      expect(s.txns.single.counterparty, 'UTI Nifty 50 Index Fund');
    });
  });

  group('Groww orders screenshot', () {
    void checkOrders(List<FundOrder> o) {
      expect(o.length, 7);
      expect(o.first.fund, 'ICICI Prudential Short Term Fund');
      expect(o.first.status, OrderStatus.inProgress);
      expect(o.first.isSip, isFalse);
      expect(o[1].fund, 'Nippon India Small Cap Fund');
      expect(o[1].date, DateTime(2026, 10, 9, 12));
      expect(o[2].fund, 'Axis Small Cap Fund');
      expect(o[2].amount, 2000);
      expect(o[3].fund, 'UTI Nifty 50 Index Fund');
      expect(o[3].amount, 9000);
      expect(o[4].fund, 'SBI Contra');
      expect(o[5].fund, 'Parag Parikh Flexi Cap Fund');
      expect(o[5].amount, 7000);
      expect(o[6].fund, 'Nippon India Pharma Fund');
      expect(o[6].date, DateTime(2026, 10, 8, 12));
      expect(o.skip(1).every((x) => x.status == OrderStatus.completed), isTrue);
      expect(o.skip(1).every((x) => x.isSip), isTrue);
    }

    test('row-by-row text', () {
      final o = FundOrdersParser.parse(growwRows, now: now);
      checkOrders(o);
      expect(o.any((x) => x.amountGuessed), isFalse);
    });

    test('column-by-column text with a misread ₹', () {
      final o = FundOrdersParser.parse(growwColumns, now: now);
      checkOrders(o);
      expect(o[2].amountGuessed, isTrue);
    });

    test('a normal payment screenshot is not an order list', () {
      expect(
        FundOrdersParser.parse(
          'Paid to\nRaju Tea Stall\n₹120\nCompleted\n5 Nov 2026, 10:00 am',
          now: now,
        ),
        isEmpty,
      );
    });

    test('chat adds completed SIPs once, matching SMS ones', () async {
      final s = await newStore();
      final e = ChatEngine(s);
      e.handle(utiSip); // already recorded from SMS (13 Oct)
      e.handle(axisSip.replaceAll('Axis MF', '09-Oct-2026 Axis MF'));
      final r = e.handleScreenshot(growwRows, now: now);
      expect(r.single.text, contains('7 mutual fund orders'));
      expect(r.single.text, contains('in progress'));
      expect(e.flow, ChatFlow.screenshot);
      final done = e.handle(addShotOption);
      expect(done.single.text, contains('Added 4 investments'));
      expect(done.single.text, contains('2 were already recorded'));
      final inv = s.txns.where(AppStore.isInvestment).toList();
      expect(inv.length, 6);
      expect(inv.map((t) => t.amount).fold(0.0, (a, b) => a + b), 22999.90);
      // Adding the same screenshot again adds nothing.
      e.handleScreenshot(growwRows, now: now);
      e.handle(addShotOption);
      expect(s.txns.where(AppStore.isInvestment).length, 6);
    });
  });

  group('Invest button', () {
    test('every investment type is offered and counted as invested', () {
      final names = investmentTypes.map((c) => c.name).toSet();
      for (final n in [
        sipCategory,
        stocksCategory,
        fdCategory,
        rdCategory,
        ppfCategory,
        epfCategory,
        npsCategory,
        goldCategory,
        bondsCategory,
        postOfficeCategory,
        sukanyaCategory,
        realEstateCategory,
        cryptoCategory,
        ulipCategory,
        p2pCategory,
        otherInvestCategory,
      ]) {
        expect(names, contains(n));
        expect(investmentCategories, contains(n));
      }
      // The Debit flow offers spending only.
      expect(
        spendingCategories.map((c) => c.name),
        isNot(contains(fdCategory)),
      );
    });

    test('manual PPF entry', () async {
      final s = await newStore();
      final e = ChatEngine(s);
      e.start(ChatFlow.invest);
      expect(e.options, contains('🐖 PPF'));
      e.handle('🐖 PPF');
      expect(e.options, contains(skipOption));
      e.handle('PPF at SBI');
      e.handle('1,50,000');
      e.handle('Today');
      e.handle(skipOption); // account
      final r = e.handle(skipOption); // note
      expect(r.first.text, contains('Invested ₹1,50,000'));
      final t = s.txns.single;
      expect(t.category, ppfCategory);
      expect(t.counterparty, 'PPF at SBI');
      expect(AppStore.isInvestment(t), isTrue);
      expect(AppStore.isSpending(t), isFalse);
    });

    test('keywords pick the new types', () {
      String g(String m) =>
          guessCategory(isCredit: false, merchant: m, message: '');
      expect(g('SAFEGOLD'), goldCategory);
      expect(g('Sovereign Gold Bond'), goldCategory);
      expect(g('PPF deposit'), ppfCategory);
      expect(g('Parag Parikh PPFAS MF'), sipCategory);
      expect(g('NPS Trust'), npsCategory);
      expect(g('WAZIRX'), cryptoCategory);
      expect(g('India Post KVP'), postOfficeCategory);
    });
  });
}
