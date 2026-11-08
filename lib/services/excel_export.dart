// Builds a multi-sheet .xlsx statement from the user's data.
//
// Sheets: Transactions, Monthly Summary, Category Summary, Accounts,
// Lend & Borrow, Reminders.

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../data/store.dart';
import '../models/models.dart';
import 'categories.dart';

class ExportRange {
  final String label;
  final DateTime? from; // inclusive; null = beginning of time
  const ExportRange(this.label, this.from);

  static List<ExportRange> presets(DateTime now) => [
    ExportRange('This month', DateTime(now.year, now.month)),
    ExportRange('Last 3 months', DateTime(now.year, now.month - 2)),
    ExportRange('Last 12 months', DateTime(now.year, now.month - 11)),
    const ExportRange('All time', null),
  ];
}

class ExcelExporter {
  static final _d = DateFormat('dd-MM-yyyy');
  static final _m = DateFormat('MMM yyyy');

  static CellValue _t(String s) => TextCellValue(s);
  static CellValue _n(double v) =>
      DoubleCellValue(double.parse(v.toStringAsFixed(2)));

  static void _header(Sheet sheet, List<String> cols) {
    sheet.appendRow(cols.map(_t).toList());
    final style = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1E6B52'),
      fontColorHex: ExcelColor.white,
    );
    for (var i = 0; i < cols.length; i++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(
                  columnIndex: i,
                  rowIndex: sheet.maxRows - 1,
                ),
              )
              .cellStyle =
          style;
      sheet.setColumnWidth(i, i == 0 ? 14 : 20);
    }
  }

  static List<int> build(AppStore store, ExportRange range) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';

    final txns =
        store.txns
            .where((t) => range.from == null || !t.date.isBefore(range.from!))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    // ---- Transactions
    final tx = excel['Transactions'];
    _header(tx, [
      'Date',
      'Type',
      'Amount (₹)',
      'Category',
      'Account',
      'Bank',
      'Account Type',
      'Last 4',
      'Merchant / Person',
      'Note',
      'Source',
      'Ref No',
      'Settled',
    ]);
    for (final t in txns) {
      final a = store.accountById(t.accountId);
      tx.appendRow([
        _t(_d.format(t.date)),
        _t(t.type.label),
        _n(t.amount),
        _t(t.category),
        _t(a?.displayName ?? ''),
        _t(a?.bank ?? ''),
        _t(a?.type.label ?? ''),
        _t(a?.last4 ?? ''),
        _t(store.merchantLabel(t.counterparty)),
        _t(t.note),
        _t(t.source == 'sms' ? 'Bank SMS' : 'Manual'),
        _t(t.refNo),
        _t(
          t.type == TxnType.lend || t.type == TxnType.borrow
              ? (t.settled ? 'Yes' : 'No')
              : '',
        ),
      ]);
    }
    bool invested(Txn t) =>
        t.type == TxnType.debit && investmentCategories.contains(t.category);
    final totalSpent = txns
        .where(AppStore.isSpending)
        .fold(0.0, (s, t) => s + t.amount);
    final totalInvested = txns
        .where(invested)
        .fold(0.0, (s, t) => s + t.amount);
    final totalIn = txns
        .where((t) => t.type == TxnType.credit)
        .fold(0.0, (s, t) => s + t.amount);
    tx.appendRow([]);
    tx.appendRow([_t('Total spent'), _t(''), _n(totalSpent)]);
    tx.appendRow([_t('Total invested (SIP etc.)'), _t(''), _n(totalInvested)]);
    tx.appendRow([_t('Total received'), _t(''), _n(totalIn)]);
    tx.appendRow([_t('Net'), _t(''), _n(totalIn - totalSpent - totalInvested)]);
    tx.appendRow([
      _t('Credit-card bill payments and investments are not counted as spent.'),
    ]);

    // ---- Monthly summary
    final monthly = excel['Monthly Summary'];
    _header(monthly, [
      'Month',
      'Spent (₹)',
      'Invested (₹)',
      'Received (₹)',
      'Net (₹)',
      'Transactions',
    ]);
    final months = <DateTime, List<Txn>>{};
    for (final t in txns) {
      months.putIfAbsent(DateTime(t.date.year, t.date.month), () => []).add(t);
    }
    for (final e in months.entries) {
      final spent = e.value
          .where(AppStore.isSpending)
          .fold(0.0, (s, t) => s + t.amount);
      final inv = e.value.where(invested).fold(0.0, (s, t) => s + t.amount);
      final recv = e.value
          .where((t) => t.type == TxnType.credit)
          .fold(0.0, (s, t) => s + t.amount);
      monthly.appendRow([
        _t(_m.format(e.key)),
        _n(spent),
        _n(inv),
        _n(recv),
        _n(recv - spent - inv),
        IntCellValue(e.value.length),
      ]);
    }

    // ---- Category summary
    final cat = excel['Category Summary'];
    _header(cat, [
      'Type',
      'Category',
      'Total (₹)',
      'Transactions',
      '% of type',
    ]);
    for (final type in [TxnType.debit, TxnType.credit]) {
      final map = <String, List<Txn>>{};
      for (final t in txns.where((t) => t.type == type)) {
        map.putIfAbsent(t.category, () => []).add(t);
      }
      final total = type == TxnType.debit ? totalSpent : totalIn;
      final entries = map.entries.toList()
        ..sort((a, b) => _sum(b.value).compareTo(_sum(a.value)));
      for (final e in entries) {
        final s = _sum(e.value);
        cat.appendRow([
          _t(
            type == TxnType.credit
                ? 'Received'
                : investmentCategories.contains(e.key)
                ? 'Invested'
                : e.key == cardBillCategory
                ? 'Card bill'
                : 'Spent',
          ),
          _t(e.key),
          _n(s),
          IntCellValue(e.value.length),
          // Share of spending only for spending categories.
          _t(
            total == 0 ||
                    (type == TxnType.debit &&
                        (investmentCategories.contains(e.key) ||
                            e.key == cardBillCategory))
                ? ''
                : '${(s / total * 100).toStringAsFixed(1)}%',
          ),
        ]);
      }
    }

    // ---- Accounts
    final acc = excel['Accounts'];
    _header(acc, [
      'Name',
      'Bank',
      'Type',
      'Last 4',
      'Spent (₹)',
      'Received (₹)',
      'Transactions',
    ]);
    for (final a in store.myAccounts) {
      final at = txns.where((t) => t.accountId == a.id).toList();
      acc.appendRow([
        _t(a.displayName),
        _t(a.bank),
        _t(a.type.label),
        _t(a.last4),
        _n(_sum(at.where((t) => t.type == TxnType.debit))),
        _n(_sum(at.where((t) => t.type == TxnType.credit))),
        IntCellValue(at.length),
      ]);
    }

    // ---- Lend & borrow (all time: outstanding debts matter regardless)
    final lb = excel['Lend & Borrow'];
    _header(lb, [
      'Date',
      'Type',
      'Person',
      'Amount (₹)',
      'Due date',
      'Settled',
      'Note',
    ]);
    for (final t in store.txns.where(
      (t) => t.type == TxnType.lend || t.type == TxnType.borrow,
    )) {
      lb.appendRow([
        _t(_d.format(t.date)),
        _t(t.type.label),
        _t(t.counterparty),
        _n(t.amount),
        _t(t.dueDate == null ? '' : _d.format(t.dueDate!)),
        _t(t.settled ? 'Yes' : 'No'),
        _t(t.note),
      ]);
    }
    lb.appendRow([]);
    lb.appendRow([
      _t('Others owe you'),
      _t(''),
      _t(''),
      _n(store.totalToReceive),
    ]);
    lb.appendRow([_t('You owe others'), _t(''), _t(''), _n(store.totalToPay)]);

    // ---- Reminders
    final rem = excel['Reminders'];
    _header(rem, ['Due date', 'Reminder', 'Amount (₹)', 'Done']);
    for (final r in store.reminders) {
      rem.appendRow([
        _t(_d.format(r.dueDate)),
        _t(r.title),
        r.amount == null ? _t('') : _n(r.amount!),
        _t(r.done ? 'Yes' : 'No'),
      ]);
    }

    excel.setDefaultSheet('Transactions');
    excel.delete(defaultSheet);
    return excel.encode()!;
  }

  static double _sum(Iterable<Txn> ts) => ts.fold(0.0, (s, t) => s + t.amount);
}
