import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/models/models.dart';
import 'package:spend_utilizer/services/sms_parser.dart';

void main() {
  final now = DateTime(2026, 11, 8, 18, 30);
  ParsedSms p(String s) {
    final r = SmsParser.parse(s, now: now);
    expect(r, isNotNull, reason: 'Could not parse: $s');
    return r!;
  }

  test('SBI UPI debit to VPA', () {
    final r = p(
      'Dear UPI user A/C X1234 debited by 250.00 on date 05Nov26 '
      'trf to SWIGGY Refno 612345678901. If not u? call 1800111109. -SBI',
    );
    expect(r.type, TxnType.debit);
    expect(r.amount, 250.0);
    expect(r.bank, 'SBI');
    expect(r.counterparty, 'SWIGGY');
    expect(r.last4, '1234');
    expect(r.accountType, AccountType.savings);
    expect(r.refNo, '612345678901');
  });

  test('SBI style debit with Rs and VPA', () {
    final r = p(
      'Rs.500.00 debited from A/c XX4567 on 05-11-26 to VPA '
      'zomato.order@axisbank (UPI Ref No 512345678901). Not you? Call '
      '1800 -SBI',
    );
    expect(r.type, TxnType.debit);
    expect(r.amount, 500.0);
    expect(r.bank, 'SBI'); // not Axis: that is the payee's UPI handle
    expect(r.last4, '4567');
    expect(r.counterparty, 'zomato.order@axisbank');
    expect(r.category, 'Food & Dining');
    expect(r.date, DateTime(2026, 11, 5, 12));
  });

  test('HDFC credit card spend', () {
    final r = p(
      'Spent Rs.1,250.50 On HDFC Bank Credit Card xx4321 At '
      'BIGBASKET On 2026-11-04:12:30:45 Avl Lmt Rs.85,000 Not You? Call '
      '18002586161',
    );
    expect(r.type, TxnType.debit);
    expect(r.amount, 1250.50);
    expect(r.bank, 'HDFC');
    expect(r.accountType, AccountType.creditCard);
    expect(r.last4, '4321');
    expect(r.counterparty, 'BIGBASKET');
    expect(r.category, 'Groceries');
    expect(r.date, DateTime(2026, 11, 4, 12, 30, 45));
  });

  test('HDFC UPI sent to a person', () {
    final r = p(
      'Sent Rs.100.00\nFrom HDFC Bank A/C *9876\nTo RAJU KUMAR\n'
      'On 06/11/26\nRef 612398765432\nNot You?\nCall 18002586161/SMS BLOCK '
      'UPI to 7308080808',
    );
    expect(r.type, TxnType.debit);
    expect(r.bank, 'HDFC');
    expect(r.last4, '9876');
    expect(r.counterparty, 'RAJU KUMAR');
    expect(r.refNo, '612398765432');
    expect(r.date, DateTime(2026, 11, 6, 12));
  });

  test('ICICI debit with merchant credited', () {
    final r = p(
      'ICICI Bank Acct XX123 debited for Rs 299.00 on 07-Nov-26; '
      'AMAZON PAY credited. UPI:612300011122. Call 18002662 for dispute.',
    );
    expect(r.type, TxnType.debit);
    expect(r.bank, 'ICICI');
    expect(r.last4, '123');
    expect(r.counterparty, 'AMAZON PAY');
    expect(r.category, 'Shopping');
    expect(r.refNo, '612300011122');
  });

  test('Kotak UPI credit received', () {
    final r = p(
      'Received Rs.2000.00 in your Kotak Bank AC X5555 from '
      'rahul.s@ybl on 03-11-26.UPI Ref:612300099988.',
    );
    expect(r.type, TxnType.credit);
    expect(r.bank, 'Kotak');
    expect(r.last4, '5555');
    expect(r.counterparty, 'rahul.s@ybl');
    expect(r.category, 'Transfer');
  });

  test('Axis debit card purchase', () {
    final r = p(
      'INR 3,499.00 spent using Axis Bank Debit Card XX7788 on '
      '01-11-2026 at MYNTRA. Avl Bal: INR 22,345.10',
    );
    expect(r.type, TxnType.debit);
    expect(r.amount, 3499.0);
    expect(r.bank, 'Axis');
    expect(r.accountType, AccountType.debitCard);
    expect(r.last4, '7788');
    expect(r.category, 'Shopping');
  });

  test('Refund is a credit with Refund category', () {
    final r = p(
      'Refund of Rs 799.00 from FLIPKART has been credited to your '
      'ICICI Bank Credit Card XX1122 on 02-Nov-26.',
    );
    expect(r.type, TxnType.credit);
    expect(r.isRefund, isTrue);
    expect(r.category, 'Refund');
    expect(r.accountType, AccountType.creditCard);
    expect(r.last4, '1122');
  });

  test('Salary credit', () {
    final r = p(
      'Your A/c XXXXXXXX5678 is credited with INR 85,000.00 on '
      '31-10-2026 by NEFT-SAL ACME TECHNOLOGIES. Avl Bal INR 1,02,000.00 '
      '-PNB',
    );
    expect(r.type, TxnType.credit);
    expect(r.amount, 85000.0);
    expect(r.bank, 'PNB');
    expect(r.last4, '5678');
    expect(r.category, 'Salary');
  });

  test('Credit card bill payment received is a credit', () {
    final r = p(
      'Payment of Rs 15,000.00 received towards your SBI Credit '
      'Card ending 4444 on 05/11/2026. Thank you.',
    );
    expect(r.type, TxnType.credit);
    expect(r.accountType, AccountType.creditCard);
    expect(r.last4, '4444');
  });

  test('Balance amount is not mistaken for transaction amount', () {
    final r = p(
      'Avl Bal Rs 10,000.00. Rs 45.00 debited from a/c XX1111 to '
      'VPA chai.wala@paytm -Canara',
    );
    expect(r.amount, 45.0);
    expect(r.bank, 'Canara');
  });

  test('Non-transaction messages are ignored', () {
    expect(
      SmsParser.parse('Your OTP for login is 123456. Do not share.', now: now),
      isNull,
    );
    expect(SmsParser.parse('hello there', now: now), isNull);
    expect(
      SmsParser.parse('Get flat Rs 500 off on your next order!', now: now),
      isNull,
    );
  });

  test('dates and times are read in many formats', () {
    DateTime d(String s) => p(s).date;
    expect(
      d('Rs 100 debited from A/c XX1234 on 03-Nov-2026 18:05 to VPA a@b'),
      DateTime(2026, 11, 3, 18, 5),
    );
    expect(
      d('INR 250 spent on Card XX1234 on Nov 02, 2026 at 10:15 PM at DMART'),
      DateTime(2026, 11, 2, 22, 15),
    );
    expect(
      d('Rs 99 debited from A/c XX1234 on 1st Nov at ZOMATO'),
      DateTime(2026, 11, 1, 12),
    );
    expect(
      d('Rs 60 debited from A/c XX1234 dated 07/11/2026 to SWIGGY'),
      DateTime(2026, 11, 7, 12),
    );
    expect(
      d('Rs 99 debited from A/c XX1234 on 06.11.26 09:41:07 UPI'),
      DateTime(2026, 11, 6, 9, 41, 7),
    );
  });

  test('missing or impossible dates fall back to now and say so', () {
    final r = p('Rs 75 debited from A/c XX1234 to VPA chai@ybl');
    expect(r.dateFound, isFalse);
    expect(r.date, now);
    final future = p('Rs 75 debited from A/c XX1234 on 25-12-2026');
    expect(future.dateFound, isFalse);
    expect(p('Rs 75 debited from A/c XX1234 on 05-11-26').dateFound, isTrue);
  });

  test('Axis credit card SMS with payment-gateway prefix', () {
    final r = p(
      'Spent INR 681\nusing Axis Bank Credit Card no. XX4676 on '
      '07-11-26 21:04:05 IST at\nPAY*BLINKIT.\nAvl limit: INR 76269.72. '
      'Not you? SMS BLOCK 4676 to +919951860002.',
    );
    expect(r.amount, 681);
    expect(r.bank, 'Axis');
    expect(r.accountType, AccountType.creditCard);
    expect(r.last4, '4676');
    expect(r.counterparty, 'BLINKIT');
    expect(r.category, 'Groceries');
    expect(r.date, DateTime(2026, 11, 7, 21, 4, 5));
  });

  test('splitMessages splits on blank lines', () {
    final parts = SmsParser.splitMessages('msg one\nline2\n\n  \nmsg two');
    expect(parts, ['msg one\nline2', 'msg two']);
  });
}
