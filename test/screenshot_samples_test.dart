// Real payment-screen layouts from Google Pay, PhonePe, BHIM, Paytm,
// MobiKwik, super.money and slice, written as on-device OCR returns them.
// All names, UPI IDs, phone numbers, account numbers and reference numbers
// are made up; the layout and the date/ID patterns are kept.

import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
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

void main() {
  final now = DateTime(2026, 11, 8, 12);
  ParsedScreenshot p(String s) {
    final r = ScreenshotParser.parse(s, now: now);
    expect(r, isNotNull, reason: s.split('\n').take(3).join(' / '));
    return r!;
  }

  Future<ScreenshotReport> check(String s) async {
    final store = AppStore(storage: MemoryStorage());
    await store.load();
    return ScreenshotChecker.check(p(s), store, now: now);
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
}
