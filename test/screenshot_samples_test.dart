// Real payment-screen layouts from Google Pay, PhonePe, BHIM, Paytm,
// MobiKwik, super.money and slice, written as on-device OCR returns them.
// All names, UPI IDs, phone numbers, account numbers and reference numbers
// are made up; the layout and the date/ID patterns are kept.

import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/models/models.dart';
import 'package:spend_utilizer/services/chat_engine.dart';
import 'package:spend_utilizer/services/screenshot_parser.dart';

const gpayPaid = '''I
To Rohan Sen
₹235
Pay again
Completed
5 Nov 2026, 9:56 pm
AU Small Finance Bank
4410
UPI transaction ID
667512345678
To: Rohan Sen
••••••1234@ptyes on Paytm
From: TEST USER (AU Small Finance Bank)
••••12-9@okaxis on Google Pay
Google transaction ID
CICAgPjI04-KJA
Google Pay''';

const gpayReceived = '''From AMIT GHOSH
+91 ••••• •4618
₹1,527.60
Completed
18 Oct 2026, 9:51am
AU Small Finance Bank 4410
UPI transaction ID
629181234567
To: TEST USER
••••98-8@okicici on Google Pay
From: AMIT GHOSH (State Bank of
India)
••••96-1@oksbi on Google Pay
Google transaction ID
CICAgPiuubzRcw
Payment summary
Train
+₹1,417.60
18 Oct • Requested by you
Split request
+₹110.00
18 Oct • Requested by you
Payments may take up to 3 working days to be reflected in your account
Google Pay''';

const phonePePaid = '''Transaction Successful
07:55 pm on 05 Nov 2026
Paid to
PD
PRIYA DAS ₹1,000
••••••1234@ybl
Banking Name : Priya Das
Transfer Details
PhonePe Transaction ID
T2611051954123456789012
Debited from
AU
XXXXXXXXXXXX4410 ₹1,000
UTR: 999112345670
Powered by
UPI YES BANK''';

const mobiKwik = '''₹5,643.72
Payment Successful
27 Oct '26 at 8:25AM
You earned ₹3.0 Cashback
Paid For
ICICI BANK
xx9002
Credit Card Bill Payment
Paid from
UPI
9876543210ab@ikwik
Au Small Finance Bank-4410
MobiKwik Order ID
MBK1419452522
Operator Ref no
MK216300BAANH3SKQ000''';

const superMoney = '''super. money
Payment Successful
₹110
November 7 at 2:00 PM
To: SHARMA DHABA
q123456789@ybl
From: TEST USER
xxxxxx1111@superyes
UPI reference ID: 667798765432
super.money UPI YES BANK
Get assured cashback on UPI spends''';

const phonePeReceived = '''Transaction Successful
09:08 am on 26 Oct 2026
Received from
NR
NEHA ROY ₹175
neharoy1998@okicici
Transfer Details
PhonePe Transaction ID
T2610260908987654321098
Credited to
AU
XXXXXXXXXXXX4410 ₹175
UTR: 629917654321
Powered by
UPI YES BANK''';

const bhimPaid = '''BHIM - Bharat's Own Payments App
Paid
₹4720.00
Banking Name
Indian Institute of Science
Bangalore
Transaction ID
122011223344
Date & Time
7th Nov 26,
12:20 pm
To UPI ID
iiscbangalore1
.bdpg@kotakp
ay
Remarks
Pay
Debited account
State Bank Of India
XXXX5521
Process details
Payment initiated by TEST USER
Payment transferred from TEST USER's account
Payment received by Indian Institute of Science Bangalore
Hide details
Split this expense
Share screenshot
UPI Help
BHIM UPI''';

const bhimReceived = '''BHIM - Bharat's Own Payments App
Received
₹46.58
Banking Name
NPCI BHIM
Transaction ID
104355667788
Date & Time
2nd Nov 26,
10:02 pm
From UPI ID
bhimcashback
@hdfcbank
Remarks
BHIMCASHBACK
Credited account
State Bank Of India
XXXX5521
Process details
Payment initiated by NPCI BHIM
Payment transferred from NPCI BHIM's account
Payment received by
Hide details
Share screenshot
BHIM UPI''';

const slice = '''Received ₹1
To slice savings
02 Aug ’26, 05:21 pm
Subscription
Details
From: Netflix
netflix.autopay@hdfcbank
To: slice savings
xx3307
Transaction ID
HDF7A60654FB7AA481DBFDF85362FFB65B7
RRN
103799887766''';

const paytmReceived = '''Paytm
Money Received
₹15
Rupees Fifteen Only
From: Paytm
Cashback
To: TEST USER
UPI ID: ******1111@ptsbi
HDFC Bank - 7712
UPI Ref No: 119012121212
10:15 PM, 27 Oct 2026
Paytm UPI SBI''';

const paytmBill = '''Paytm
Order Successful
₹500
Rupees Five Hundred Only
For: Bill Payment of
SBI Bank Credit Card
XXXX XXXX XXXX
6630
UPI ID: ccbillpay@ptybl
From: TEST USER
UPI ID: ******1111@ptyes
AU Small Finance Bank -
4410
Order ID: 27830352217
UPI Ref No: 219134343434
10:22 PM, 27 Oct 2026
Paytm UPI YES BANK''';

// slice "Paid" screen, with the status bar and a "Pay again" button on
// the name line, as the phone's text reader returns it.
const slicePaid = '''19:21
9%
Paid ₹26
To Sharma Caterers Itgn Pay again
07 Nov ’26, 05:44 pm
Notes: UPI
Claim reward
Play and win
Food & dining Edit
Details Share
From: slice CC
RuPay xx7731
To: Sharma Caterers Itgn
q0123456789@ybl''';

const slicePaid2 = '''19:15
10%
Paid ₹60
To Vendor Stall 03
Pay again
08 Nov ’26, 02:47 pm
Notes: UPI
Claim reward
Play and win
Groceries
Edit
Details
Share
From: slice CC
RuPay xx7731
To: Vendor Stall 03
paytm.d1234567890@pty''';

// UPI-on-credit-card screen: payee in the header, card under "Payment
// method", and the bold "₹120" read by OCR as "7120".
const cardUpiPaid = '''23:10
44%
J
Juice Corner
paytm.a1b2c3d@pty
Help
7120
Payment Successful
November 3 at 10:24 PM
You have earned 3% cashback
Paid to:
paytm.a1b2c3d@pty
UPI Reference ID
667312345678
Payment method
Axis CC XX24
Check limit
View more
Share
Past Transactions
November '26
You Sent
7120
3rd Nov • 10:24 PM
From
Pay again
Done''';

// CRED credit-card bill payment.
const credBill = '''19:26
84%
transaction detail
AMOUNT
₹2,000
PAYMENT SUCCESSFUL
payment received
24 OCT 12:00 PM
paid using upi
view details
deposited to card
24 OCT 12:01 PM
SBI will consider 24 Oct as
the payment date. contact
support for queries.
know more
order id
XA123BCD456E
utr
1ABC2D33EFG45HIJKL6M7NO8PQR1234
0630
Bharat Connect transaction id
DP123456A7B8CDEFG90H
Download documents''';

// CRED bill for an Axis card, with a "100% late fee protection" line.
const credBillAxis = '''19:28
83%
transaction detail
AMOUNT
₹1,104
PAYMENT SUCCESSFUL
payment received
20 SEP 2:53 PM
paid using upi
view details
deposited to card
20 SEP 2:53 PM
Axis Bank has confirmed your
payment and will consider 20
Sep as the payment date.
contact support for queries
know more
100% late fee protection
know more
order id
AB1CD2EFGH3J
utr
ABC1D234EFGHIJKL5M6NOPQRST123
456789
Bharat Connect transaction id
DP123456ABC1234D5E67''';

// CRED payment receipt: "<payer> paid" / "<payee>".
const credPaid = '''Rahul paid
Amit Verma
₹10
Paid via CRED
paid securely by
CRED
02:40pm, 20th oct'26 | 665912345678''';

void main() {
  final now = DateTime(2026, 11, 8, 12);
  ParsedScreenshot p(String s) {
    final r = ScreenshotParser.parse(s, now: now);
    expect(r, isNotNull, reason: s.split('\n').take(3).join(' / '));
    return r!;
  }

  Future<ScreenshotReport> check(String s, {DateTime? at}) async {
    final store = AppStore(storage: MemoryStorage());
    await store.load();
    return ScreenshotChecker.check(p(s), store, now: at ?? now);
  }

  void expect5(
    ParsedScreenshot r, {
    required PaymentApp app,
    required bool received,
    required double amount,
    required String who,
    required DateTime date,
    required String bank,
    required String last4,
    required String utr,
  }) {
    expect(r.app, app);
    expect(r.status, PaymentStatus.success);
    expect(r.received, received);
    expect(r.amount, amount);
    expect(r.who, who);
    expect(r.date, date);
    expect(r.bank, bank);
    expect(r.last4, last4);
    expect(r.utr, utr);
  }

  test('Google Pay: paid', () {
    expect5(
      p(gpayPaid),
      app: PaymentApp.googlePay,
      received: false,
      amount: 235,
      who: 'Rohan Sen',
      date: DateTime(2026, 11, 5, 21, 56),
      bank: 'AU Bank',
      last4: '4410',
      utr: '667512345678',
    );
  });

  test('Google Pay: received', () {
    expect5(
      p(gpayReceived),
      app: PaymentApp.googlePay,
      received: true,
      amount: 1527.60,
      who: 'AMIT GHOSH',
      date: DateTime(2026, 10, 18, 9, 51),
      bank: 'AU Bank',
      last4: '4410',
      utr: '629181234567',
    );
  });

  test('PhonePe: paid (bank shown only as a logo)', () {
    final r = p(phonePePaid);
    expect5(
      r,
      app: PaymentApp.phonePe,
      received: false,
      amount: 1000,
      who: 'PRIYA DAS',
      date: DateTime(2026, 11, 5, 19, 55),
      bank: 'Unknown Bank',
      last4: '4410',
      utr: '999112345670',
    );
    expect(r.appTxnId, 'T2611051954123456789012');
  });

  test('PhonePe: received', () {
    final r = p(phonePeReceived);
    expect5(
      r,
      app: PaymentApp.phonePe,
      received: true,
      amount: 175,
      who: 'NEHA ROY',
      date: DateTime(2026, 10, 26, 9, 8),
      bank: 'Unknown Bank',
      last4: '4410',
      utr: '629917654321',
    );
    expect(r.upiId, 'neharoy1998@okicici');
  });

  test('BHIM: paid (name and date wrap onto two lines)', () {
    expect5(
      p(bhimPaid),
      app: PaymentApp.bhim,
      received: false,
      amount: 4720,
      who: 'Indian Institute of Science Bangalore',
      date: DateTime(2026, 11, 7, 12, 20),
      bank: 'SBI',
      last4: '5521',
      utr: '122011223344',
    );
  });

  test('BHIM: received', () {
    expect5(
      p(bhimReceived),
      app: PaymentApp.bhim,
      received: true,
      amount: 46.58,
      who: 'NPCI BHIM',
      date: DateTime(2026, 11, 2, 22, 2),
      bank: 'SBI',
      last4: '5521',
      utr: '104355667788',
    );
  });

  test('MobiKwik: credit card bill (card being paid is not mine)', () {
    expect5(
      p(mobiKwik),
      app: PaymentApp.mobiKwik,
      received: false,
      amount: 5643.72,
      who: 'ICICI BANK',
      date: DateTime(2026, 10, 27, 8, 25),
      bank: 'AU Bank',
      last4: '4410',
      utr: '',
    );
  });

  test('super.money: date without a year, digits inside UPI ID ignored', () {
    final r = p(superMoney);
    expect5(
      r,
      app: PaymentApp.superMoney,
      received: false,
      amount: 110,
      who: 'SHARMA DHABA',
      date: DateTime(2026, 11, 7, 14, 0),
      bank: 'Unknown Bank',
      last4: '',
      utr: '667798765432',
    );
    expect(r.upiId, 'q123456789@ybl');
  });

  test('slice: received', () {
    final r = p(slice);
    expect5(
      r,
      app: PaymentApp.slice,
      received: true,
      amount: 1,
      who: 'Netflix',
      date: DateTime(2026, 8, 2, 17, 21),
      bank: 'Slice',
      last4: '3307',
      utr: '103799887766',
    );
    expect(r.upiId, 'netflix.autopay@hdfcbank');
  });

  test('Paytm: received (footer "SBI" is not my bank)', () {
    final r = p(paytmReceived);
    expect5(
      r,
      app: PaymentApp.paytm,
      received: true,
      amount: 15,
      who: 'Paytm Cashback',
      date: DateTime(2026, 10, 27, 22, 15),
      bank: 'HDFC',
      last4: '7712',
      utr: '119012121212',
    );
    expect(r.amountInWords, 15);
  });

  test('Paytm: bill payment', () {
    final r = p(paytmBill);
    expect5(
      r,
      app: PaymentApp.paytm,
      received: false,
      amount: 500,
      who: 'Bill Payment of SBI Bank Credit Card',
      date: DateTime(2026, 10, 27, 22, 22),
      bank: 'AU Bank',
      last4: '4410',
      utr: '219134343434',
    );
    expect(r.upiId, 'ccbillpay@ptybl');
    expect(r.amountInWords, 500);
  });

  group('checks on genuine screenshots', () {
    for (final (name, s) in [
      ('gpayPaid', gpayPaid),
      ('gpayReceived', gpayReceived),
      ('phonePePaid', phonePePaid),
      ('phonePeReceived', phonePeReceived),
      ('bhimPaid', bhimPaid),
      ('bhimReceived', bhimReceived),
      ('mobiKwik', mobiKwik),
      ('superMoney', superMoney),
      ('slice', slice),
      ('paytmReceived', paytmReceived),
      ('paytmBill', paytmBill),
    ]) {
      test('$name is not called suspicious', () async {
        final r = await check(s);
        expect(
          r.verdict,
          isNot(Verdict.suspicious),
          reason: r.checks.map((c) => '${c.icon} ${c.text}').join('\n'),
        );
      });
    }

    test('positive signals are found', () async {
      String all(ScreenshotReport r) => r.checks.map((c) => c.text).join('\n');
      expect(all(await check(gpayReceived)), contains('matches the date'));
      expect(all(await check(phonePeReceived)), contains('matches the date'));
      expect(
        all(await check(phonePePaid)),
        contains('transaction ID matches the date and time'),
      );
      expect(
        all(await check(paytmReceived)),
        contains('amount in words matches'),
      );
    });
  });

  group('checks on edited screenshots', () {
    test('Paytm amount changed but words left as they were', () async {
      final r = await check(paytmReceived.replaceFirst('₹15', '₹1500'));
      expect(r.verdict, Verdict.suspicious);
      expect(r.checks.map((c) => c.text).join(), contains('amount in words'));
    });

    test('PhonePe date changed', () async {
      final r = await check(
        phonePePaid.replaceFirst('05 Nov 2026', '07 Nov 2026'),
      );
      expect(r.verdict, Verdict.suspicious);
      expect(
        r.checks.map((c) => c.text).join(),
        contains("doesn't match the time shown"),
      );
    });

    test('PhonePe time changed', () async {
      final r = await check(
        phonePeReceived.replaceFirst('09:08 am', '11:40 am'),
      );
      expect(r.verdict, Verdict.suspicious);
    });

    test(
      'received screenshot with a date-coded reference that disagrees',
      () async {
        final r = await check(
          gpayReceived.replaceFirst('18 Oct 2026', '1 Nov 2026'),
        );
        expect(
          r.checks.any(
            (c) =>
                c.level == CheckLevel.warn && c.text.contains('may point to'),
          ),
          isTrue,
        );
      },
    );
  });

  group('slice paid screens', () {
    test('reads amount, payee, card, date and category', () {
      final r = p(slicePaid);
      expect(r.app, PaymentApp.slice);
      expect(r.received, isFalse);
      expect(r.amount, 26);
      expect(r.who, 'Sharma Caterers Itgn');
      expect(r.date, DateTime(2026, 11, 7, 17, 44));
      expect(r.bank, 'Slice');
      expect(r.last4, '7731');
      expect(r.accountType, AccountType.creditCard);
      expect(r.appCategory, 'Food & Dining');
      expect(r.utr, '');

      final r2 = p(slicePaid2);
      expect(r2.amount, 60);
      expect(r2.who, 'Vendor Stall 03');
      expect(r2.date, DateTime(2026, 11, 8, 14, 47));
      expect(r2.appCategory, 'Groceries');
      expect(r2.upiId, 'paytm.d1234567890@pty');
    });

    for (final misread in ['Z26', '%26', '*26', '?26', '26', 'z 26']) {
      test('"Paid ₹26" read as "Paid $misread"', () {
        expect(
          p(slicePaid.replaceFirst('Paid ₹26', 'Paid $misread')).amount,
          26,
        );
      });
    }

    test('not called suspicious; phone clock after payment is fine', () async {
      // Checked the same evening, as on the phone (clock 19:15–19:21).
      for (final s in [slicePaid, slicePaid2]) {
        final r = await check(s, at: DateTime(2026, 11, 8, 19, 25));
        expect(
          r.verdict,
          isNot(Verdict.suspicious),
          reason: r.checks.map((c) => c.text).join('\n'),
        );
      }
    });

    test('added as a credit-card payment in the shown category', () async {
      final store = AppStore(storage: MemoryStorage());
      await store.load();
      final e = ChatEngine(store);
      e.handleScreenshot(slicePaid, now: now);
      e.handle(addShotOption);
      final t = store.txns.single;
      expect(t.amount, 26);
      expect(t.category, 'Food & Dining');
      final acc = store.accountById(t.accountId)!;
      expect(acc.bank, 'Slice');
      expect(acc.type, AccountType.creditCard);
      expect(acc.last4, '7731');
    });
  });

  group('CRED', () {
    test('credit-card bill payment', () {
      final r = p(credBill);
      expect(r.app, PaymentApp.cred);
      expect(r.status, PaymentStatus.success);
      expect(r.received, isFalse);
      expect(r.amount, 2000);
      expect(r.who, 'SBI Credit Card bill');
      expect(r.date, DateTime(2026, 10, 24, 12, 0));
      expect(r.utr, ''); // CRED's "utr" here isn't a 12-digit UPI reference
    });

    test('credit-card bill for an Axis card', () {
      final r = p(credBillAxis);
      expect(r.app, PaymentApp.cred);
      expect(r.amount, 1104);
      expect(r.who, 'Axis Credit Card bill');
      expect(r.date, DateTime(2026, 9, 20, 14, 53));
      expect(r.utr, '');
    });

    test('payment receipt', () {
      final r = p(credPaid);
      expect(r.app, PaymentApp.cred);
      expect(r.received, isFalse);
      expect(r.amount, 10);
      expect(r.who, 'Amit Verma');
      expect(r.date, DateTime(2026, 10, 20, 14, 40));
      expect(r.utr, '665912345678');
    });

    test('neither is called suspicious', () async {
      for (final s in [credBill, credBillAxis, credPaid]) {
        final r = await check(s);
        expect(
          r.verdict,
          isNot(Verdict.suspicious),
          reason: r.checks.map((c) => c.text).join('\n'),
        );
      }
    });

    test('bill payments are filed as Credit Card Bill, not spending', () async {
      final store = AppStore(storage: MemoryStorage());
      await store.load();
      final e = ChatEngine(store);
      for (final s in [credBill, credBillAxis, paytmBill, mobiKwik]) {
        e.handleScreenshot(s, now: now);
        e.handle(addShotOption);
        if (e.active) e.cancel(); // skip "is this account yours?"
      }
      expect(store.txns.length, 4);
      expect(
        store.txns.every((t) => t.category == 'Credit Card Bill'),
        isTrue,
        reason: store.txns.map((t) => t.category).join(', '),
      );
      e.handleScreenshot(credPaid, now: now);
      e.handle(addShotOption);
      final oct = DateTime(2026, 10);
      // Only the ₹10 payment counts as spending in October.
      expect(store.spentIn(oct), 10);
      expect(
        store
            .categoryTotals(oct, TxnType.debit)
            .any((c) => c.category == 'Credit Card Bill'),
        isFalse,
      );
    });
  });

  group('₹ read as 7', () {
    test(
      'UPI on a credit card: payee in header, card under Payment method',
      () {
        final r = p(cardUpiPaid);
        expect(r.amount, 120);
        expect(r.amountGuessed, isTrue);
        expect(r.app, PaymentApp.other); // "paytm" only inside the UPI ID
        expect(r.received, isFalse);
        expect(r.who, 'Juice Corner');
        expect(r.upiId, 'paytm.a1b2c3d@pty');
        expect(r.date, DateTime(2026, 11, 3, 22, 24));
        expect(r.utr, '667312345678');
        expect(r.bank, 'Axis');
        expect(r.last4, '24');
        expect(r.accountType, AccountType.creditCard);
      },
    );

    test('fixed using the same amount elsewhere on the screen', () {
      final shown = cardUpiPaid.replaceFirst(
        'You Sent\n7120',
        'You Sent\n₹120',
      );
      expect(p(shown).amount, 120);
    });

    test('a real amount starting with 7 is left alone', () {
      expect(p(cardUpiPaid.replaceAll('7120', '₹7,120')).amount, 7120);
      expect(p(cardUpiPaid.replaceAll('7120', '7,120')).amount, 7120);
      expect(p(cardUpiPaid.replaceAll('7120', '₹712')).amount, 712);
    });

    test('the guess is flagged for the user to check', () async {
      final r = await check(cardUpiPaid);
      expect(
        r.checks.map((c) => c.text).join(),
        contains("₹ sign wasn't clear"),
      );
      expect(r.verdict, isNot(Verdict.suspicious));
    });
  });
}
