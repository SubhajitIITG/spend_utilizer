import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/models/models.dart';
import 'package:spend_utilizer/services/categories.dart';
import 'package:spend_utilizer/services/excel_export.dart';
import 'package:spend_utilizer/services/pdf_export.dart';
import 'package:spend_utilizer/util/period.dart';

Future<AppStore> seeded() async {
  final s = AppStore(storage: MemoryStorage());
  await s.load();
  var n = 0;
  void add(TxnType type, double amt, String cat, DateTime d) => s.addTxn(
    Txn(id: 't${n++}', type: type, amount: amt, category: cat, date: d),
  );
  add(TxnType.debit, 100, 'Food & Dining', DateTime(2026, 9, 10));
  add(TxnType.debit, 200, 'Shopping', DateTime(2026, 10, 1));
  add(TxnType.debit, 5000, sipCategory, DateTime(2026, 10, 5));
  add(TxnType.debit, 300, 'Food & Dining', DateTime(2026, 11, 15, 23, 30));
  add(TxnType.debit, 9000, cardBillCategory, DateTime(2026, 11, 2));
  add(TxnType.debit, 10000, fdCategory, DateTime(2026, 11, 3));
  add(TxnType.credit, 50000, 'Salary', DateTime(2026, 11, 1));
  return s;
}

void main() {
  group('Period', () {
    test('month covers whole calendar month', () {
      final p = Period.month(DateTime(2026, 2, 14));
      expect(p.from, DateTime(2026, 2, 1));
      expect(p.to, DateTime(2026, 2, 28));
      expect(p.contains(DateTime(2026, 2, 28, 23, 59)), isTrue);
      expect(p.contains(DateTime(2026, 3, 1)), isFalse);
      expect(p.label, 'February 2026');
      expect(p.fileTag, '2026-02');
      expect(p.shiftMonths(-2), Period.month(DateTime(2025, 12)));
    });

    test('custom range swaps reversed dates and includes both ends', () {
      final p = Period.custom(DateTime(2026, 11, 15), DateTime(2026, 10, 1));
      expect(p.from, DateTime(2026, 10, 1));
      expect(p.to, DateTime(2026, 11, 15));
      expect(p.isMonth, isFalse);
      expect(p.contains(DateTime(2026, 11, 15, 22)), isTrue);
      expect(p.contains(DateTime(2026, 9, 30, 23)), isFalse);
      expect(p.label, '1 Oct – 15 Nov 2026');
      expect(p.fileTag, '2026-10-01_to_2026-11-15');
    });

    test('presets', () {
      final now = DateTime(2026, 11, 9);
      expect(Period.lastMonths(3, now).from, DateTime(2026, 9, 1));
      expect(Period.thisYear(now).from, DateTime(2026, 1, 1));
      expect(Period.allTime(now).label, 'All time');
    });
  });

  test('range totals split spent, invested and card bills', () async {
    final s = await seeded();
    final nov = Period.month(DateTime(2026, 11));
    expect(s.spentDuring(nov), 300); // card bill & FD not spending
    expect(s.investedDuring(nov), 10000);
    expect(s.receivedDuring(nov), 50000);

    final range = Period.custom(DateTime(2026, 9, 1), DateTime(2026, 11, 15));
    expect(s.spentDuring(range), 600);
    expect(s.investedDuring(range), 15000);
    final cats = s.categoryTotalsDuring(range, TxnType.debit);
    expect(cats.first.category, 'Food & Dining');
    expect(cats.first.amount, 400);
    expect(cats.map((c) => c.category), isNot(contains(sipCategory)));

    final oct = Period.custom(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
    expect(s.txnsIn(oct).length, 2);
  });

  test('excel export only includes the chosen period', () async {
    final s = await seeded();
    final p = Period.custom(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
    final x = Excel.decodeBytes(ExcelExporter.build(s, p));
    final rows = x.tables['Transactions']!.rows;
    final dates = rows
        .skip(1)
        .map((r) => r.isEmpty ? '' : r.first?.value.toString() ?? '')
        .where((v) => RegExp(r'^\d\d-\d\d-\d{4}$').hasMatch(v))
        .toList();
    expect(dates, ['01-10-2026', '05-10-2026']);
    final flat = rows.expand((r) => r).map((c) => c?.value.toString());
    expect(flat, contains('Period: ${p.label}'));
  });

  test('pdf export builds a document', () async {
    final s = await seeded();
    Future<ByteData> font(String f) async =>
        ByteData.sublistView(await File('assets/fonts/pdf/$f').readAsBytes());
    final bytes = await PdfExporter.build(
      s,
      Period.custom(DateTime(2026, 9, 1), DateTime(2026, 11, 30)),
      regular: await font('DejaVuSerif.ttf'),
      bold: await font('DejaVuSerif-Bold.ttf'),
      now: DateTime(2026, 11, 9),
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(2000));

    // An empty period still renders.
    final empty = await PdfExporter.build(
      s,
      Period.month(DateTime(2020, 1)),
      regular: await font('DejaVuSerif.ttf'),
      bold: await font('DejaVuSerif-Bold.ttf'),
    );
    expect(String.fromCharCodes(empty.take(4)), '%PDF');
  });
}
