// Builds a printable PDF statement for a period: summary, spending by
// category, investments, lend & borrow, and every transaction.

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/store.dart';
import '../models/models.dart';
import '../util/format.dart';
import '../util/period.dart';
import 'categories.dart';

class PdfExporter {
  static const _wine = PdfColor.fromInt(0xFF6E1233);
  static const _gold = PdfColor.fromInt(0xFFC9A13B);
  static const _navy = PdfColor.fromInt(0xFF0F2742);
  static const _ink = PdfColor.fromInt(0xFF231218);
  static const _muted = PdfColor.fromInt(0xFF6B5560);
  static const _paper = PdfColor.fromInt(0xFFF8F1E5);
  static const _green = PdfColor.fromInt(0xFF2D6A4F);
  static const _red = PdfColor.fromInt(0xFFA4161A);

  /// [regular] and [bold] are TrueType fonts with the ₹ sign (DejaVu
  /// Serif, bundled in assets/fonts/pdf).
  static Future<Uint8List> build(
    AppStore store,
    Period period, {
    required ByteData regular,
    required ByteData bold,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
    final doc = pw.Document(
      title: 'Spend Utilizer statement – ${period.label}',
      author: 'Spend Utilizer',
      theme: theme,
    );

    final txns = store.txnsIn(period).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final spent = store.spentDuring(period);
    final received = store.receivedDuring(period);
    final invested = store.investedDuring(period);
    final net = received - spent - invested;
    final cats = store.categoryTotalsDuring(period, TxnType.debit);
    final investments = store.investmentsDuring(period);
    final dateFmt = DateFormat('dd MMM yyyy');

    pw.Widget heading(String text) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 18, bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _gold, width: 0.8)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: _wine,
        ),
      ),
    );

    pw.Widget box(String label, double value, PdfColor color) => pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 3),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: _paper,
          border: pw.Border.all(color: _gold, width: 0.6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${value < 0 ? '−' : ''}${money(value.abs())}',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );

    pw.Widget table(
      List<String> headers,
      List<List<String>> rows, {
      Map<int, pw.Alignment> align = const {},
      Map<int, pw.TableColumnWidth>? widths,
      PdfColor? Function(int row, int col)? colorOf,
    }) {
      return pw.Table(
        columnWidths: widths,
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
        ),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _navy),
            children: [
              for (var c = 0; c < headers.length; c++)
                pw.Container(
                  alignment: align[c] ?? pw.Alignment.centerLeft,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 4,
                  ),
                  child: pw.Text(
                    headers[c],
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          for (var r = 0; r < rows.length; r++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: r.isOdd ? _paper : PdfColors.white,
              ),
              children: [
                for (var c = 0; c < rows[r].length; c++)
                  pw.Container(
                    alignment: align[c] ?? pw.Alignment.centerLeft,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    child: pw.Text(
                      rows[r][c],
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: colorOf?.call(r, c) ?? _ink,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      );
    }

    String share(double v, double total) =>
        total == 0 ? '' : '${(v / total * 100).toStringAsFixed(1)}%';

    // Investments by type.
    final byType = <String, double>{};
    for (final t in investments) {
      byType[t.category] = (byType[t.category] ?? 0) + t.amount;
    }
    final people = store.personBalances();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  'Spend Utilizer · ${period.label}',
                  style: const pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ),
        footer: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Credit-card bill payments and investments are not counted '
                'as spent.',
                style: const pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
              pw.Text(
                'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          // Title band
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: _navy,
              border: pw.Border.all(color: _gold, width: 1),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Spend Utilizer',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: _gold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Statement · ${period.label}',
                        style: const pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  '${dateFmt.format(period.from)} – '
                  '${dateFmt.format(period.to)}\n'
                  'Generated ${DateFormat('dd MMM yyyy, h:mm a').format(at)}',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey300,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              box('Spent', spent, _red),
              box('Received', received, _green),
              box('Invested', invested, _gold),
              box('Net', net, net >= 0 ? _green : _red),
            ],
          ),

          heading('Spending by category'),
          if (cats.isEmpty)
            pw.Text(
              'No spending in this period.',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            )
          else
            table(
              ['Category', 'Amount', 'Share'],
              [
                for (final c in cats)
                  [c.category, money(c.amount), share(c.amount, spent)],
              ],
              align: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
              widths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.4),
                2: const pw.FlexColumnWidth(1),
              },
            ),

          if (byType.isNotEmpty) ...[
            heading('Investments'),
            table(
              ['Type', 'Amount'],
              [
                for (final cat in investmentCategoryOrder)
                  if (byType.containsKey(cat))
                    [
                      cat == otherInvestCategory ? 'Other investments' : cat,
                      money(byType[cat]!),
                    ],
              ],
              align: {1: pw.Alignment.centerRight},
              widths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.4),
              },
            ),
          ],

          if (people.isNotEmpty) ...[
            heading('Lend & borrow (outstanding today)'),
            table(
              ['Person', 'Status'],
              [
                for (final p in people)
                  [
                    p.person,
                    p.amount > 0
                        ? 'Owes you ${money(p.amount)}'
                        : 'You owe ${money(-p.amount)}',
                  ],
              ],
              align: {1: pw.Alignment.centerRight},
            ),
          ],

          heading('Transactions (${txns.length})'),
          if (txns.isEmpty)
            pw.Text(
              'No transactions in this period.',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            )
          else
            table(
              ['Date', 'Details', 'Category', 'Account', 'Amount'],
              [
                for (final t in txns)
                  [
                    dateFmt.format(t.date),
                    [
                      t.counterparty.isNotEmpty
                          ? store.merchantLabel(t.counterparty)
                          : t.category,
                      if (t.note.isNotEmpty) t.note,
                    ].join(' · '),
                    t.category,
                    store.accountById(t.accountId)?.displayName ?? '',
                    '${t.type.isOutflow ? '−' : '+'}${money(t.amount)}',
                  ],
              ],
              align: {4: pw.Alignment.centerRight},
              widths: {
                0: const pw.FlexColumnWidth(1.25),
                1: const pw.FlexColumnWidth(2.6),
                2: const pw.FlexColumnWidth(1.6),
                3: const pw.FlexColumnWidth(1.8),
                4: const pw.FlexColumnWidth(1.25),
              },
              colorOf: (r, c) =>
                  c == 4 ? (txns[r].type.isOutflow ? _red : _green) : null,
            ),
        ],
      ),
    );
    return doc.save();
  }
}
