import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../services/excel_export.dart';
import '../services/pdf_export.dart';
import '../util/period.dart';

/// Lets the user choose a period: quick presets or any start–end dates.
/// Returns null if they dismiss the sheet.
Future<Period?> pickPeriod(
  BuildContext context, {
  required Period current,
  bool forExport = false,
}) async {
  final now = DateTime.now();
  final presets = <(String, Period)>[
    ('This month', Period.month(now)),
    ('Last month', Period.month(DateTime(now.year, now.month - 1))),
    ('Last 3 months', Period.lastMonths(3, now)),
    if (forExport) ('Last 12 months', Period.lastMonths(12, now)),
    ('This year', Period.thisYear(now)),
    if (forExport) ('All time', Period.allTime(now)),
  ];

  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Show period',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          for (final (label, p) in presets)
            ListTile(
              leading: Icon(
                p == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(label),
              subtitle: Text(p.label),
              onTap: () => Navigator.pop(ctx, p),
            ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Custom range…'),
            subtitle: const Text('Pick a start and end date'),
            onTap: () => Navigator.pop(ctx, 'custom'),
          ),
        ],
      ),
    ),
  );
  if (choice is Period) return choice;
  if (choice != 'custom' || !context.mounted) return null;

  final today = DateTime(now.year, now.month, now.day);
  final initialEnd = current.to.isAfter(today) ? today : current.to;
  final initialStart = current.from.isAfter(initialEnd)
      ? initialEnd
      : current.from;
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: today,
    initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    helpText: 'Choose start and end date',
    saveText: 'Apply',
  );
  if (range == null) return null;
  return Period.custom(range.start, range.end);
}

enum StatementFormat { excel, pdf }

/// Shows the download dialog (period + Excel/PDF), builds the statement and
/// lets the user choose where to save it.
Future<void> exportStatement(BuildContext context, {Period? initial}) async {
  final store = context.read<AppStore>();
  final messenger = ScaffoldMessenger.of(context);
  var period = initial ?? Period.month(DateTime.now());
  var format = StatementFormat.excel;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Download statement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Period'),
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final p = await pickPeriod(
                  ctx,
                  current: period,
                  forExport: true,
                );
                if (p != null) setState(() => period = p);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Icon(Icons.edit_calendar),
                ),
                child: Text(period.label, key: const Key('export-period')),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Format'),
            const SizedBox(height: 4),
            SegmentedButton<StatementFormat>(
              segments: const [
                ButtonSegment(
                  value: StatementFormat.excel,
                  icon: Icon(Icons.table_chart_outlined),
                  label: Text('Excel'),
                ),
                ButtonSegment(
                  value: StatementFormat.pdf,
                  icon: Icon(Icons.picture_as_pdf_outlined),
                  label: Text('PDF'),
                ),
              ],
              selected: {format},
              onSelectionChanged: (s) => setState(() => format = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              '${store.txnsIn(period).length} transactions in this period',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
        ],
      ),
    ),
  );
  if (go != true) return;

  try {
    final Uint8List bytes;
    final String ext, mime;
    if (format == StatementFormat.pdf) {
      final regular = await rootBundle.load('assets/fonts/pdf/DejaVuSerif.ttf');
      final bold = await rootBundle.load(
        'assets/fonts/pdf/DejaVuSerif-Bold.ttf',
      );
      bytes = await PdfExporter.build(
        store,
        period,
        regular: regular,
        bold: bold,
      );
      ext = 'pdf';
      mime = 'application/pdf';
    } else {
      bytes = Uint8List.fromList(ExcelExporter.build(store, period));
      ext = 'xlsx';
      mime =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    final name = 'SpendUtilizer_${period.fileTag}.$ext';
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save statement',
      fileName: name,
      bytes: bytes,
      mimeType: mime,
    );
    if (uri == null) return; // user cancelled
    messenger.showSnackBar(SnackBar(content: Text('Saved $name')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}
