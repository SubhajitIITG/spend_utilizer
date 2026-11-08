import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../services/categories.dart';
import '../util/format.dart';

Future<void> showTxnEditor(BuildContext context, Txn txn) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<AppStore>(),
      child: _TxnEditor(txn: txn),
    ),
  );
}

class _TxnEditor extends StatefulWidget {
  final Txn txn;
  const _TxnEditor({required this.txn});
  @override
  State<_TxnEditor> createState() => _TxnEditorState();
}

class _TxnEditorState extends State<_TxnEditor> {
  late TxnType _type = widget.txn.type;
  late final _amount = TextEditingController(
    text: _fmtAmount(widget.txn.amount),
  );
  late String _category = widget.txn.category;
  late String? _accountId = widget.txn.accountId;
  late final _who = TextEditingController(text: widget.txn.counterparty);
  late final _note = TextEditingController(text: widget.txn.note);
  late DateTime _date = widget.txn.date;
  late bool _settled = widget.txn.settled;

  static String _fmtAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  List<String> get _categoryChoices {
    final base = switch (_type) {
      TxnType.credit => creditCategories.map((c) => c.name).toList(),
      TxnType.debit => debitCategories.map((c) => c.name).toList(),
      TxnType.lend => [lendCategory],
      TxnType.borrow => [borrowCategory],
    };
    if (!base.contains(_category)) base.insert(0, _category);
    return base;
  }

  void _onTypeChanged(TxnType t) {
    setState(() {
      _type = t;
      final choices = _categoryChoices;
      if (t == TxnType.lend) _category = lendCategory;
      if (t == TxnType.borrow) _category = borrowCategory;
      if (!choices.contains(_category) ||
          _category == lendCategory ||
          _category == borrowCategory) {
        _category = t == TxnType.lend
            ? lendCategory
            : t == TxnType.borrow
            ? borrowCategory
            : 'Others';
      }
    });
  }

  void _save() {
    final v = parseAmount(_amount.text);
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    final store = context.read<AppStore>();
    final categoryChanged = _category != widget.txn.category;
    final t = widget.txn
      ..type = _type
      ..amount = v
      ..accountId = _accountId
      ..counterparty = _who.text.trim()
      ..note = _note.text.trim()
      ..date = _date;
    if (categoryChanged) {
      // Also teaches the app this merchant's category.
      store.recategorize(t, _category);
    } else {
      store.updateTxn(t);
    }
    if (t.type == TxnType.lend || t.type == TxnType.borrow) {
      store.setSettled(t, _settled);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final t = widget.txn;
    final isDebt = _type == TxnType.lend || _type == TxnType.borrow;
    final accountIds = store.selectableAccounts.map((a) => a.id).toSet();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        left: 16,
        right: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Edit transaction',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SegmentedButton<TxnType>(
              segments: [
                for (final ty in TxnType.values)
                  ButtonSegment(value: ty, label: Text(ty.label)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => _onTypeChanged(s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in _categoryChoices)
                  DropdownMenuItem(value: c, child: Text('${emojiFor(c)} $c')),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: accountIds.contains(_accountId) ? _accountId : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Account / card',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('— None —'),
                ),
                for (final a in store.selectableAccounts)
                  DropdownMenuItem<String?>(
                    value: a.id,
                    child: Text(a.displayName),
                  ),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _who,
              decoration: InputDecoration(
                labelText: isDebt ? 'Person' : 'Merchant / payee',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(formatDate(_date)),
              trailing: const Text('Change'),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (d != null) {
                  setState(
                    () => _date = DateTime(
                      d.year,
                      d.month,
                      d.day,
                      _date.hour,
                      _date.minute,
                    ),
                  );
                }
              },
            ),
            if (isDebt)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _type == TxnType.lend
                      ? 'Money returned to me'
                      : 'I have repaid this',
                ),
                value: _settled,
                onChanged: (v) => setState(() => _settled = v),
              ),
            if (t.rawMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Original bank message'),
                children: [
                  SelectableText(
                    t.rawMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  onPressed: () {
                    store.deleteTxn(t);
                    Navigator.pop(context);
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
