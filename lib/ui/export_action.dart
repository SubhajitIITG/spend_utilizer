import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../services/excel_export.dart';

/// Asks for a date range, builds the Excel statement and lets the user
/// choose where to save it.
Future<void> exportToExcel(BuildContext context) async {
  final store = context.read<AppStore>();
  final messenger = ScaffoldMessenger.of(context);
  final range = await showDialog<ExportRange>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Download Excel statement'),
      children: [
        for (final r in ExportRange.presets(DateTime.now()))
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(r.label),
            ),
          ),
      ],
    ),
  );
  if (range == null) return;

  try {
    final bytes = Uint8List.fromList(ExcelExporter.build(store, range));
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final name = 'SpendUtilizer_${range.label.replaceAll(' ', '')}_$stamp.xlsx';
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save Excel statement',
      fileName: name,
      bytes: bytes,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (uri == null) return; // user cancelled
    messenger.showSnackBar(SnackBar(content: Text('Saved $name')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}
