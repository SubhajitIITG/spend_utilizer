import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/models/models.dart';
import 'package:spend_utilizer/services/chat_engine.dart';
import 'package:spend_utilizer/services/excel_export.dart';

const hdfcCard1 = 'Spent Rs.500 On HDFC Bank Credit Card xx1111 At SWIGGY '
    'On 2026-11-04:10:00:00 Avl Lmt Rs.50,000';
const hdfcCard2 = 'Spent Rs.900 On HDFC Bank Credit Card xx2222 At AMAZON '
    'On 2026-11-04:11:00:00 Avl Lmt Rs.90,000';
const hdfcCard3 = 'Spent Rs.300 On HDFC Bank Credit Card xx3333 At UBER '
    'On 2026-11-04:12:00:00 Avl Lmt Rs.30,000';
const sbiSavings = 'Rs.200.00 debited from A/c XX4567 on 05-11-26 to VPA '
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
  });

  test('credit flow offers refund category', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    e.start(ChatFlow.credit);
    e.handle('499');
    expect(e.options, contains('↩️ Refund'));
    e.handle('↩️ Refund');
    e.handle('Cash');
    final done = e.handle('Skip');
    final t = s.txnById(done.single.txnId)!;
    expect(t.category, 'Refund');
    expect(s.accountById(t.accountId)!.type, AccountType.cash);
  });

  test('lend and borrow track people and create reminders', () async {
    final s = await newStore();
    final e = ChatEngine(s);
    e.start(ChatFlow.lend);
    e.handle('Rahul');
    e.handle('2000');
    e.handle('Skip');
    e.handle('In 1 week');
    e.handle('Skip');
    e.start(ChatFlow.borrow);
    e.handle('Priya');
    e.handle('500');
    e.handle('Skip');
    e.handle('No reminder');
    e.handle('Skip');

    expect(s.totalToReceive, 2000);
    expect(s.totalToPay, 500);
    expect(s.reminders.single.title, contains('Rahul'));

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
    expect(replies.last.text, contains('2 added'));
    expect(replies.last.text, contains('1 not understood'));
  });

  test('excel export has all sheets and rows', () async {
    final s = await newStore();
    s.addFromSms(hdfcCard1);
    s.addFromSms(sbiSavings);
    final bytes = ExcelExporter.build(s, const ExportRange('All time', null));
    final x = Excel.decodeBytes(bytes);
    expect(
        x.tables.keys,
        containsAll([
          'Transactions', 'Monthly Summary', 'Category Summary', 'Accounts',
          'Lend & Borrow', 'Reminders',
        ]));
    expect(x.tables.keys, isNot(contains('Sheet1')));
    final rows = x.tables['Transactions']!.rows;
    expect(rows.first.first!.value.toString(), 'Date');
    expect(rows.length, greaterThanOrEqualTo(3));
  });
}
