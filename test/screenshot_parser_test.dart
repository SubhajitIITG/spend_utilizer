import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/services/chat_engine.dart';
import 'package:spend_utilizer/services/screenshot_parser.dart';

// OCR text in the shape ML Kit returns for common success screens.
// 8 Nov 2026 is day 312 of the year, 7 Nov is day 311.

const gpayPaid = '''10:45
₹500
Paid to RAJU KUMAR
raju.k1987@okaxis
Completed
8 Nov 2026, 10:42 am
UPI transaction ID
631210421234
To: RAJU KUMAR
Google Pay • raju.k1987@okaxis
From: SUBHAJIT KALA (State Bank of India)
State Bank of India ••••4567
Google transaction ID
CICAgMDQ0bXhYQ''';

const phonePeReceived = '''9:15
Transaction Successful
08:58 pm on 07 Nov 2026
Received from
PRIYA SHARMA
priya.s@ybl
₹1,250
Transfer Details
Transaction ID
T2611072058123456789012
Credited to
XXXXXXXX1234
UTR: 631120581234''';

// Someone changed the visible date to 8 Nov; the IDs still say 5 Nov.
const phonePeFake = '''9:15
Transaction Successful
08:58 am on 08 Nov 2026
Received from
PRIYA SHARMA
priya.s@ybl
₹5,000
Transaction ID
T2611050858123456789012
UTR: 630908581234''';

const paytmPaid = '''Paytm
Paid Successfully
Z250
To: CHAI POINT
chaipoint@paytm
08 Nov, 09:15 AM
UPI Ref No: 631209153344
From: HDFC Bank - 9876''';

const bhimFailed = '''Transaction Failed
Rs. 300.00
Paid to
MEDPLUS PHARMACY
UPI Transaction ID: 631208001111
08/11/2026 08:00 AM''';

void main() {
  final now = DateTime(2026, 11, 8, 11, 0);

  test('Google Pay payment screen', () {
    final p = ScreenshotParser.parse(gpayPaid, now: now)!;
    expect(p.app, PaymentApp.googlePay);
    expect(p.status, PaymentStatus.success);
    expect(p.received, isFalse);
    expect(p.amount, 500);
    expect(p.counterparty, 'RAJU KUMAR');
    expect(p.upiId, 'raju.k1987@okaxis');
    expect(p.date, DateTime(2026, 11, 8, 10, 42));
    expect(p.hasTime, isTrue);
    expect(p.utr, '631210421234');
    expect(p.bank, 'SBI');
    expect(p.last4, '4567');
    expect(p.statusBarTime, (10, 45));
  });

  test('PhonePe money received screen', () {
    final p = ScreenshotParser.parse(phonePeReceived, now: now)!;
    expect(p.app, PaymentApp.phonePe);
    expect(p.received, isTrue);
    expect(p.amount, 1250);
    expect(p.counterparty, 'PRIYA SHARMA');
    expect(p.upiId, 'priya.s@ybl');
    expect(p.date, DateTime(2026, 11, 7, 20, 58));
    expect(p.utr, '631120581234');
    expect(p.appTxnId, 'T2611072058123456789012');
    expect(p.last4, '1234');
  });

  test('Paytm with OCR-mangled rupee sign and no year', () {
    final p = ScreenshotParser.parse(paytmPaid, now: now)!;
    expect(p.app, PaymentApp.paytm);
    expect(p.amount, 250);
    expect(p.counterparty, 'CHAI POINT');
    expect(p.date, DateTime(2026, 11, 8, 9, 15));
    expect(p.utr, '631209153344');
    expect(p.bank, 'HDFC');
    expect(p.last4, '9876');
  });

  test('failed payment is reported as failed', () {
    final p = ScreenshotParser.parse(bhimFailed, now: now)!;
    expect(p.status, PaymentStatus.failed);
    expect(p.amount, 300);
    expect(p.counterparty, 'MEDPLUS PHARMACY');
    final r = ScreenshotChecker.check(
      p,
      AppStore(storage: MemoryStorage()),
      now: now,
    );
    expect(r.verdict, Verdict.suspicious);
    expect(r.checks.first.text, contains('failed'));
  });

  test('not a payment screenshot', () {
    expect(ScreenshotParser.parse('Hello\nHow are you?', now: now), isNull);
    expect(ScreenshotParser.parse('', now: now), isNull);
  });

  group('checks', () {
    late AppStore store;
    setUp(() async {
      store = AppStore(storage: MemoryStorage());
      await store.load();
    });

    test('genuine-looking payment: consistent, not verified', () {
      final p = ScreenshotParser.parse(gpayPaid, now: now)!;
      final r = ScreenshotChecker.check(p, store, now: now);
      expect(r.verdict, Verdict.consistent);
      expect(r.checks.map((c) => c.text).join(), contains('matches the date'));
      expect(r.checks.any((c) => c.level == CheckLevel.bad), isFalse);
    });

    test('edited date is caught by the reference numbers', () {
      final p = ScreenshotParser.parse(phonePeFake, now: now)!;
      final r = ScreenshotChecker.check(p, store, now: now);
      expect(r.verdict, Verdict.suspicious);
      final bad = r.checks.where((c) => c.level == CheckLevel.bad).toList();
      expect(bad.length, 1); // PhonePe transaction ID (UTR is only a warning)
      expect(bad.first.text, contains('5 Nov 2026'));
    });

    test('screenshot taken before the payment time', () {
      final edited = gpayPaid.replaceFirst('10:45', '10:30');
      final p = ScreenshotParser.parse(edited, now: now)!;
      final r = ScreenshotChecker.check(p, store, now: now);
      expect(r.verdict, Verdict.suspicious);
      expect(r.checks.map((c) => c.text).join(), contains('phone clock'));
    });

    test('future date is suspicious', () {
      final p = ScreenshotParser.parse(
        gpayPaid.replaceFirst('8 Nov 2026', '9 Nov 2026'),
        now: now,
      )!;
      final r = ScreenshotChecker.check(p, store, now: now);
      expect(r.checks.map((c) => c.text).join(), contains('future'));
    });

    test('received payment verified by matching bank SMS', () {
      store.addFromSms(
        'Your A/c XX1234 is credited with Rs.1,250.00 on '
        '07-11-26 by UPI Ref 631120581234 -SBI',
      );
      final p = ScreenshotParser.parse(phonePeReceived, now: now)!;
      final r = ScreenshotChecker.check(p, store, now: now);
      expect(r.verdict, Verdict.verified);
      expect(r.alreadyRecorded, isNotNull);
    });

    test('received payment without SMS asks to check the bank', () {
      final p = ScreenshotParser.parse(phonePeReceived, now: now)!;
      final r = ScreenshotChecker.check(p, store, now: now);
      expect(r.verdict, Verdict.consistent);
      expect(
        r.checks.map((c) => c.text).join(),
        contains('No matching credit'),
      );
    });

    test('same screenshot added twice is noticed', () {
      final p = ScreenshotParser.parse(gpayPaid, now: now)!;
      store.addFromScreenshot(
        received: false,
        amount: p.amount,
        counterparty: p.who,
        date: p.date!,
        refNo: p.utr,
        bank: p.bank,
        last4: p.last4,
        category: 'Others',
        rawText: p.rawText,
      );
      final r = ScreenshotChecker.check(p, store, now: now);
      expect(r.alreadyRecorded, isNotNull);
      expect(r.checks.map((c) => c.text).join(), contains('already added'));
    });

    test('same reference with a different amount is flagged', () {
      store.addFromSms(
        'Rs.50.00 debited from A/c XX4567 on 08-11-26 to VPA '
        'raju.k1987@okaxis (UPI Ref No 631210421234) -SBI',
      );
      final p = ScreenshotParser.parse(gpayPaid, now: now)!;
      final r = ScreenshotChecker.check(p, store, now: now);
      expect(r.verdict, Verdict.suspicious);
    });
  });

  group('chat', () {
    late AppStore store;
    late ChatEngine e;
    setUp(() async {
      store = AppStore(storage: MemoryStorage());
      await store.load();
      e = ChatEngine(store);
    });

    test('screenshot is read, checked, and added on request', () {
      final r = e.handleScreenshot(gpayPaid, now: now);
      final text = r.single.text;
      expect(text, contains('Google Pay'));
      expect(text, contains('Paid ₹500 to RAJU KUMAR'));
      expect(text, contains('matches the date'));
      expect(text, contains('Add it as a debit?'));
      expect(e.flow, ChatFlow.screenshot);
      expect(e.options, [addShotOption, skipShotOption]);

      final added = e.handle(addShotOption);
      final t = store.txns.single;
      expect(t.source, 'screenshot');
      expect(t.amount, 500);
      expect(t.refNo, '631210421234');
      expect(t.date, DateTime(2026, 11, 8, 10, 42));
      expect(added.first.txnId, t.id);
      // The SBI account seen on the screen gets the "is this yours?" check.
      expect(e.flow, ChatFlow.ownership);
    });

    test('choosing not to add adds nothing', () {
      e.handleScreenshot(gpayPaid, now: now);
      e.handle(skipShotOption);
      expect(store.txns, isEmpty);
      expect(e.active, isFalse);
    });

    test('failed payments and already-recorded ones are not offered', () {
      expect(
        e.handleScreenshot(bhimFailed, now: now).single.text,
        contains('payment failed'),
      );
      expect(e.active, isFalse);

      store.addFromSms(
        'Your A/c XX1234 is credited with Rs.1,250.00 on '
        '07-11-26 by UPI Ref 631120581234 -SBI',
      );
      final r = e.handleScreenshot(phonePeReceived, now: now).single.text;
      expect(r, contains('Verified'));
      expect(r, contains('already in your records'));
      expect(store.txns.length, 1);
    });

    test('later bank SMS for a screenshot payment is not double-counted', () {
      e.handleScreenshot(gpayPaid, now: now);
      e.handle(addShotOption);
      final res = store.addFromSms(
        'Rs.500.00 debited from A/c XX4567 on '
        '08-11-26 to VPA raju.k1987@okaxis (UPI Ref No 631210421234) -SBI',
      );
      expect(res.status, SmsStatus.duplicate);
      expect(store.txns.length, 1);
    });

    test('no text, unreadable text and errors are explained', () {
      expect(
        e.handleScreenshot('', now: now).single.text,
        contains('couldn\'t find any text'),
      );
      final r = e.handleScreenshot('Some app\nHello there', now: now);
      expect(r.single.text, contains('This is what I could read'));
      expect(r.single.text, contains('Hello there'));
      expect(
        e.screenshotError(Exception('boom')).single.text,
        contains('boom'),
      );
    });
  });
}
