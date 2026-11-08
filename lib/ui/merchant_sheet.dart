import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../services/categories.dart';
import '../util/format.dart';
import 'theme.dart';

/// Bottom sheet to tell the app what a merchant / UPI ID is: a friend or a
/// shop category, plus an optional friendly name.
Future<void> showMerchantSheet(
  BuildContext context, {
  required String counterparty,
  String? summary,
}) {
  final store = context.read<AppStore>();
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _MerchantSheet(
      counterparty: counterparty,
      summary: summary,
      store: store,
      onDone: (msg) => messenger.showSnackBar(SnackBar(content: Text(msg))),
    ),
  );
}

class _MerchantSheet extends StatefulWidget {
  final String counterparty;
  final String? summary;
  final AppStore store;
  final void Function(String) onDone;
  const _MerchantSheet({
    required this.counterparty,
    required this.summary,
    required this.store,
    required this.onDone,
  });

  @override
  State<_MerchantSheet> createState() => _MerchantSheetState();
}

class _MerchantSheetState extends State<_MerchantSheet> {
  late final MerchantRule? _rule = widget.store.merchantRule(
    widget.counterparty,
  );
  late String? _category = (_rule?.decided ?? false) ? _rule!.category : null;
  late final _alias = TextEditingController(text: _rule?.alias ?? '');

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  void _save() {
    final c = _category;
    if (c == null) return;
    final changed = widget.store.setMerchantCategory(
      widget.counterparty,
      c,
      alias: _alias.text,
      isPerson: c == friendsCategory,
    );
    Navigator.pop(context);
    widget.onDone(
      'Saved. $changed payment${changed == 1 ? '' : 's'} updated; future '
      'ones will follow automatically.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cats = [
      debitCategories.firstWhere((c) => c.name == friendsCategory),
      ...debitCategories.where((c) => c.name != friendsCategory),
    ];
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('What is this?', style: t.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.counterparty,
              style: t.bodyMedium?.copyWith(color: Royal.gold),
            ),
            if (widget.summary != null) ...[
              const SizedBox(height: 4),
              Text(widget.summary!, style: t.bodySmall),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cats)
                  ChoiceChip(
                    label: Text(
                      c.name == friendsCategory
                          ? '👤 A friend / person'
                          : '${c.emoji} ${c.name}',
                    ),
                    selected: _category == c.name,
                    onSelected: (_) => setState(() => _category = c.name),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _alias,
              decoration: InputDecoration(
                labelText: _category == friendsCategory
                    ? 'Their name (optional)'
                    : 'Friendly name (optional)',
                hintText: _category == friendsCategory
                    ? 'e.g. Rahul'
                    : 'e.g. Raju Tea Stall',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _category == null ? null : _save,
              child: const Text('Save'),
            ),
            if (_rule == null || !_rule.decided) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        widget.store.snoozeMerchant(widget.counterparty);
                        Navigator.pop(context);
                      },
                      child: const Text('Ask me later'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        widget.store.neverAskMerchant(widget.counterparty);
                        Navigator.pop(context);
                      },
                      child: const Text('Don\'t ask again'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One-line description of a regular-payment suggestion.
String describeSuggestion(MerchantSuggestion m) {
  final range = m.minAmount == m.maxAmount
      ? money(m.minAmount)
      : '${money(m.minAmount)}–${money(m.maxAmount)}';
  return '${m.count} payments in ${m.days} day${m.days == 1 ? '' : 's'} · '
      '$range each · ${money(m.total)} total';
}

/// Lists the merchants the app has learned about, to review or change.
class MerchantsScreen extends StatelessWidget {
  const MerchantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final pending = store.merchantsToReview();
    final known = store.merchants.values.where((m) => m.decided).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    String labelFor(String key) {
      for (final t in store.txns.reversed) {
        if (merchantKey(t.counterparty) == key) return t.counterparty.trim();
      }
      return key;
    }

    return Scaffold(
      appBar: royalAppBar('Merchants'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              if (pending.isNotEmpty) ...[
                const _Header('Needs your input'),
                for (final m in pending)
                  ListTile(
                    leading: const Icon(Icons.help_outline, color: Royal.gold),
                    title: Text(m.label),
                    subtitle: Text(describeSuggestion(m)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showMerchantSheet(
                      context,
                      counterparty: m.label,
                      summary: describeSuggestion(m),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              const _Header('Learned'),
              if (known.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Nothing yet. When you change the category of a payment, '
                    'or answer a question about a regular payment, the app '
                    'remembers it here.',
                  ),
                ),
              for (final m in known)
                ListTile(
                  leading: Text(
                    m.isPerson ? '👤' : emojiFor(m.category),
                    style: const TextStyle(fontSize: 22),
                  ),
                  title: Text(m.alias.isNotEmpty ? m.alias : labelFor(m.key)),
                  subtitle: Text(
                    [
                      m.category,
                      if (m.alias.isNotEmpty) labelFor(m.key),
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () =>
                      showMerchantSheet(context, counterparty: labelFor(m.key)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Royal.gold,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );
}
