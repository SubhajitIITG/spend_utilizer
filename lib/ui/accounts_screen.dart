import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../util/format.dart';
import 'theme.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final byBank = <String, List<Account>>{};
    for (final a in store.accounts) {
      byBank.putIfAbsent(a.bank, () => []).add(a);
    }
    final now = DateTime.now();

    return Scaffold(
      appBar: royalAppBar('Banks & Cards'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editAccount(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add account'),
      ),
      body: store.accounts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No accounts yet.\nPaste a bank SMS in Chat and your bank '
                  'accounts and cards will appear here automatically.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  children: [
                    for (final e in byBank.entries)
                      Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          children: [
                            ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: Royal.gradient,
                                ),
                                child: Text(
                                  e.key.isEmpty ? '?' : e.key[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Royal.goldLight,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(
                                e.key,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: Text(_bankSummary(e.value)),
                              trailing: e.key == 'Cash'
                                  ? null
                                  : IconButton(
                                      tooltip: 'Rename bank',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () =>
                                          _renameBank(context, e.key),
                                    ),
                            ),
                            const Divider(height: 1),
                            for (final a in e.value)
                              ListTile(
                                leading: Icon(
                                  _iconFor(a.type),
                                  color: Royal.gold,
                                ),
                                title: Text(a.displayName),
                                subtitle: Text(
                                  '${a.type.label}'
                                  '${a.last4.isEmpty ? '' : ' ••${a.last4}'}'
                                  ' · ${money(store.accountSpentIn(a, now))} '
                                  'spent this month',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _editAccount(context, a),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  static String _bankSummary(List<Account> list) {
    final cards = list.where((a) => a.type.isCard).length;
    final accs = list.length - cards;
    return [
      if (accs > 0) '$accs account${accs == 1 ? '' : 's'}',
      if (cards > 0) '$cards card${cards == 1 ? '' : 's'}',
    ].join(' · ');
  }

  Future<void> _renameBank(BuildContext context, String bank) async {
    final store = context.read<AppStore>();
    final c = TextEditingController(text: bank);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename bank'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Bank name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      store.renameBank(bank, name);
    }
  }

  Future<void> _editAccount(BuildContext context, Account? existing) async {
    final store = context.read<AppStore>();
    final bank = TextEditingController(text: existing?.bank ?? '');
    final nick = TextEditingController(text: existing?.nickname ?? '');
    final last4 = TextEditingController(text: existing?.last4 ?? '');
    var type = existing?.type ?? AccountType.savings;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Add account' : 'Edit account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nick,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. HDFC Millennia, Salary account',
                  ),
                ),
                TextField(
                  controller: bank,
                  decoration: const InputDecoration(labelText: 'Bank'),
                ),
                DropdownButtonFormField<AccountType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final t in AccountType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
                TextField(
                  controller: last4,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Last 4 digits',
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == 'delete' && existing != null) {
      store.deleteAccount(existing);
    } else if (result == 'save') {
      final bankName = bank.text.trim().isEmpty
          ? (type == AccountType.cash ? 'Cash' : 'Unknown Bank')
          : bank.text.trim();
      if (existing == null) {
        store.addAccount(
          Account(
            id: store.newId(),
            bank: bankName,
            type: type,
            last4: last4.text.trim(),
            nickname: nick.text.trim(),
          ),
        );
      } else {
        store.updateAccount(
          existing,
          bank: bankName,
          nickname: nick.text,
          type: type,
          last4: last4.text,
        );
      }
    }
  }
}

IconData _iconFor(AccountType t) => switch (t) {
  AccountType.creditCard => Icons.credit_card,
  AccountType.debitCard => Icons.payment,
  AccountType.savings => Icons.account_balance,
  AccountType.wallet => Icons.account_balance_wallet,
  AccountType.cash => Icons.payments_outlined,
};
