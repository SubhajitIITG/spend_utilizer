import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../services/categories.dart';
import '../util/format.dart';
import 'export_action.dart';
import 'theme.dart';
import 'txn_editor.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  TxnType? _filter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final q = _query.toLowerCase();
    final list = store.txns.where((t) {
      if (_filter != null && t.type != _filter) return false;
      if (q.isEmpty) return true;
      final acc = store.accountById(t.accountId)?.displayName ?? '';
      return t.counterparty.toLowerCase().contains(q) ||
          t.category.toLowerCase().contains(q) ||
          t.note.toLowerCase().contains(q) ||
          acc.toLowerCase().contains(q) ||
          t.amount.toString().contains(q);
    }).toList()..sort((a, b) => b.date.compareTo(a.date));

    // Group by day.
    final groups = <DateTime, List<Txn>>{};
    for (final t in list) {
      groups
          .putIfAbsent(
            DateTime(t.date.year, t.date.month, t.date.day),
            () => [],
          )
          .add(t);
    }

    return Scaffold(
      appBar: royalAppBar(
        'History',
        actions: [
          IconButton(
            tooltip: 'Download Excel statement',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => exportToExcel(context),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search merchant, person, category, account…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final f in <TxnType?>[null, ...TxnType.values])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f == null ? 'All' : f.label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(child: Text('No transactions yet.'))
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          for (final e in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Row(
                                children: [
                                  Text(
                                    formatDayHeader(e.key),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      height: 0.8,
                                      color: Royal.gold.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final t in e.value) TxnTile(txn: t),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TxnTile extends StatelessWidget {
  final Txn txn;
  const TxnTile({super.key, required this.txn});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final acc = store.accountById(txn.accountId);
    final scheme = Theme.of(context).colorScheme;
    final out = txn.type.isOutflow;
    final title = txn.counterparty.isNotEmpty
        ? store.merchantLabel(txn.counterparty)
        : txn.category;
    final subtitle = [
      formatTxnDate(txn.date),
      if (txn.counterparty.isNotEmpty) txn.category,
      if (acc != null) acc.displayName,
      if (txn.note.isNotEmpty) txn.note,
      if ((txn.type == TxnType.lend || txn.type == TxnType.borrow))
        txn.settled ? 'Settled ✓' : 'Pending',
    ].join(' · ');
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHigh,
          border: Border.all(color: Royal.gold.withValues(alpha: 0.6)),
        ),
        child: Text(
          emojiFor(txn.category),
          style: const TextStyle(fontSize: 18),
        ),
      ),
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${out ? '−' : '+'}${money(txn.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: out ? Royal.spend(context) : Royal.income(context),
            ),
          ),
          if (txn.source == 'sms')
            Text('from SMS', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      onTap: () => showTxnEditor(context, txn),
    );
  }
}
