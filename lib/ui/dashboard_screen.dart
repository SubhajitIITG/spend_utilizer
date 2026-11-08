import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../services/categories.dart';
import '../util/format.dart';
import 'export_action.dart';
import 'profile_screen.dart';

const _chartColors = [
  Color(0xFF1E6B52), Color(0xFFE07A5F), Color(0xFF3D5A80), Color(0xFFF2CC8F),
  Color(0xFF81B29A), Color(0xFF9C6ADE), Color(0xFFEF476F), Color(0xFF118AB2),
  Color(0xFFFFB703), Color(0xFF8D99AE),
];

class DashboardScreen extends StatefulWidget {
  final VoidCallback onOpenAccounts;
  const DashboardScreen({super.key, required this.onOpenAccounts});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  TxnType _breakdown = TxnType.debit;

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          const SyncStatusButton(),
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
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              IconButton(
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text(formatMonth(_month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                  onPressed: isCurrent ? null : () => _shift(1),
                  icon: const Icon(Icons.chevron_right)),
            ]),
            _SummaryRow(store: store, month: _month),
            const SizedBox(height: 12),
            _Section(
              title: 'Where your money went',
              trailing: SegmentedButton<TxnType>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: TxnType.debit, label: Text('Spent')),
                  ButtonSegment(value: TxnType.credit, label: Text('Received')),
                ],
                selected: {_breakdown},
                onSelectionChanged: (s) =>
                    setState(() => _breakdown = s.first),
              ),
              child: _CategoryBreakdown(
                  totals: store.categoryTotals(_month, _breakdown)),
            ),
            _Section(
              title: 'Your banks & cards',
              trailing: TextButton(
                  onPressed: widget.onOpenAccounts,
                  child: const Text('Manage')),
              child: _AccountsOverview(store: store, month: _month),
            ),
            _Section(
              title: 'Lend & borrow',
              child: _DebtsOverview(store: store),
            ),
            _Section(
              title: 'Reminders',
              child: _RemindersList(store: store),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _Section({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ?trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final AppStore store;
  final DateTime month;
  const _SummaryRow({required this.store, required this.month});

  @override
  Widget build(BuildContext context) {
    final spent = store.spentIn(month);
    final recv = store.receivedIn(month);
    final net = recv - spent;
    final scheme = Theme.of(context).colorScheme;
    Widget tile(String label, double v, Color color, IconData icon) =>
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(label,
                          style: Theme.of(context).textTheme.labelMedium,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(money(v),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: color)),
                  ),
                ],
              ),
            ),
          ),
        );
    return Row(children: [
      tile('Spent', spent, scheme.error, Icons.arrow_upward),
      tile('Received', recv, Colors.green.shade700, Icons.arrow_downward),
      tile('Net', net, net >= 0 ? Colors.green.shade700 : scheme.error,
          Icons.account_balance_wallet_outlined),
    ]);
  }
}

class _CategoryBreakdown extends StatelessWidget {
  final List<CategoryTotal> totals;
  const _CategoryBreakdown({required this.totals});

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No transactions this month yet. Paste a bank SMS in '
            'Chat to get started.'),
      );
    }
    final sum = totals.fold(0.0, (s, c) => s + c.amount);
    final chart = SizedBox(
      height: 180,
      width: 180,
      child: PieChart(PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 46,
        sections: [
          for (var i = 0; i < totals.length; i++)
            PieChartSectionData(
              value: totals[i].amount,
              color: _chartColors[i % _chartColors.length],
              radius: 36,
              title: totals[i].amount / sum >= 0.08
                  ? '${(totals[i].amount / sum * 100).round()}%'
                  : '',
              titleStyle: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
        ],
      )),
    );
    final legend = Column(children: [
      for (var i = 0; i < totals.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: _chartColors[i % _chartColors.length],
                  shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  '${emojiFor(totals[i].category)} ${totals[i].category}',
                  overflow: TextOverflow.ellipsis),
            ),
            Text(money(totals[i].amount),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
    ]);
    return LayoutBuilder(builder: (ctx, c) {
      if (c.maxWidth >= 520) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          chart,
          const SizedBox(width: 24),
          Expanded(child: legend),
        ]);
      }
      return Column(children: [chart, const SizedBox(height: 12), legend]);
    });
  }
}

class _AccountsOverview extends StatelessWidget {
  final AppStore store;
  final DateTime month;
  const _AccountsOverview({required this.store, required this.month});

  @override
  Widget build(BuildContext context) {
    if (store.accounts.isEmpty) {
      return const Text('Accounts and cards are detected automatically from '
          'your bank messages.');
    }
    final byBank = <String, List<Account>>{};
    for (final a in store.accounts) {
      byBank.putIfAbsent(a.bank, () => []).add(a);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(label: Text('🏦 ${store.banks.length} banks')),
          Chip(label: Text('💳 ${store.cardCount} cards')),
          Chip(label: Text('📒 ${store.bankAccountCount} accounts')),
        ]),
        const SizedBox(height: 8),
        for (final e in byBank.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(e.key,
                style: Theme.of(context).textTheme.labelLarge),
          ),
          for (final a in e.value)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_iconFor(a.type)),
              title: Text(a.displayName),
              // The auto name already says type + last digits; only
              // repeat them when the user has given a custom name.
              subtitle: a.nickname.isEmpty
                  ? null
                  : Text('${a.type.label}'
                      '${a.last4.isEmpty ? '' : ' ••${a.last4}'}'),
              trailing: Text('${money(store.accountSpentIn(a, month))} spent'),
            ),
        ],
      ],
    );
  }
}

IconData _iconFor(AccountType t) => switch (t) {
      AccountType.creditCard => Icons.credit_card,
      AccountType.debitCard => Icons.payment,
      AccountType.savings => Icons.account_balance,
      AccountType.wallet => Icons.account_balance_wallet,
      AccountType.cash => Icons.payments_outlined,
    };

class _DebtsOverview extends StatelessWidget {
  final AppStore store;
  const _DebtsOverview({required this.store});

  @override
  Widget build(BuildContext context) {
    final people = store.personBalances();
    if (people.isEmpty) {
      return const Text('Nothing pending. Use Lend / Borrow in Chat to '
          'track money with friends.');
    }
    return Column(children: [
      Row(children: [
        Expanded(
          child: Text('You\'ll get ${money(store.totalToReceive)}',
              style: TextStyle(
                  color: Colors.green.shade700, fontWeight: FontWeight.w600)),
        ),
        Text('You owe ${money(store.totalToPay)}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600)),
      ]),
      const Divider(),
      for (final p in people)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
              child: Text(p.person.isEmpty ? '?' : p.person[0].toUpperCase())),
          title: Text(p.person),
          trailing: Text(
            p.amount > 0
                ? 'owes you ${money(p.amount)}'
                : 'you owe ${money(-p.amount)}',
            style: TextStyle(
                color: p.amount > 0
                    ? Colors.green.shade700
                    : Theme.of(context).colorScheme.error),
          ),
        ),
    ]);
  }
}

class _RemindersList extends StatelessWidget {
  final AppStore store;
  const _RemindersList({required this.store});

  @override
  Widget build(BuildContext context) {
    final pending = store.pendingReminders;
    if (pending.isEmpty) {
      return const Text('No upcoming reminders.');
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Column(children: [
      for (final r in pending)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: r.done,
          onChanged: (_) => store.toggleReminder(r),
          title: Text(r.title),
          subtitle: Text(
            '${formatDate(r.dueDate)}'
            '${r.dueDate.isBefore(today) ? ' · overdue' : ''}',
            style: r.dueDate.isBefore(today)
                ? TextStyle(color: Theme.of(context).colorScheme.error)
                : null,
          ),
          secondary: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => store.deleteReminder(r),
          ),
        ),
    ]);
  }
}
