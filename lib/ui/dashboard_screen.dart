import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../services/categories.dart';
import '../util/format.dart';
import 'export_action.dart';
import 'merchant_sheet.dart';
import 'profile_screen.dart';
import 'theme.dart';

const _chartColors = Royal.chartColors;

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
      appBar: royalAppBar(
        'Dashboard',
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
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _HeroCard(
                store: store,
                month: _month,
                onPrev: () => _shift(-1),
                onNext: isCurrent ? null : () => _shift(1),
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'Where your money went',
                trailing: SegmentedButton<TxnType>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: TxnType.debit, label: Text('Spent')),
                    ButtonSegment(
                      value: TxnType.credit,
                      label: Text('Received'),
                    ),
                  ],
                  selected: {_breakdown},
                  onSelectionChanged: (s) =>
                      setState(() => _breakdown = s.first),
                ),
                child: _CategoryBreakdown(
                  totals: store.categoryTotals(_month, _breakdown),
                ),
              ),
              if (store.merchantsToReview().isNotEmpty)
                _Section(
                  title: 'Regular payments to review',
                  child: _MerchantReview(store: store),
                ),
              _Section(
                title: 'Your banks & cards',
                trailing: TextButton(
                  onPressed: widget.onOpenAccounts,
                  child: const Text('Manage'),
                ),
                child: _AccountsOverview(store: store, month: _month),
              ),
              if (store.sipsInYear(_month.year).isNotEmpty)
                _Section(
                  title: 'SIP & Mutual Funds',
                  child: _SipOverview(store: store, month: _month),
                ),
              _Section(
                title: 'Lend & borrow',
                child: _DebtsOverview(store: store),
              ),
              _Section(
                title: 'Reminders',
                child: _RemindersList(store: store),
              ),
            ],
          ),
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
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: Royal.goldGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final AppStore store;
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const _HeroCard({
    required this.store,
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final spent = store.spentIn(month);
    final recv = store.receivedIn(month);
    final invested = store.investedIn(month);
    // What's left after spending and investing.
    final net = recv - spent - invested;
    final count = store.txnsInMonth(month).length;
    const muted = TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5);

    Widget stat(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: muted),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        // Midnight navy panel framed by a fine gold rule.
        color: Royal.navy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Royal.gold, width: 1.2),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                color: Royal.goldLight,
                disabledColor: Colors.white24,
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  formatMonth(month).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Royal.goldLight,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                color: Royal.goldLight,
                disabledColor: Colors.white24,
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total spent', style: muted),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ShaderMask(
                    shaderCallback: (r) => Royal.goldGradient.createShader(r),
                    child: Text(
                      money(spent),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count transaction${count == 1 ? '' : 's'}',
                  style: muted,
                ),
                const SizedBox(height: 14),
                Container(
                  height: 0.8,
                  color: Royal.gold.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    stat('Received', money(recv), const Color(0xFF8FE3B5)),
                    stat('Invested', money(invested), Royal.goldLight),
                    stat(
                      'Net',
                      '${net < 0 ? '−' : ''}${money(net.abs())}',
                      net >= 0
                          ? const Color(0xFF8FE3B5)
                          : const Color(0xFFFFA19A),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
        child: Text(
          'No transactions this month yet. Paste a bank SMS in '
          'Chat to get started.',
        ),
      );
    }
    final sum = totals.fold(0.0, (s, c) => s + c.amount);
    final chart = SizedBox(
      height: 180,
      width: 180,
      child: PieChart(
        PieChartData(
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
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
    final legend = Column(
      children: [
        for (var i = 0; i < totals.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _chartColors[i % _chartColors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${emojiFor(totals[i].category)} ${totals[i].category}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  money(totals[i].amount),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (ctx, c) {
        if (c.maxWidth >= 520) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chart,
              const SizedBox(width: 24),
              Expanded(child: legend),
            ],
          );
        }
        return Column(children: [chart, const SizedBox(height: 12), legend]);
      },
    );
  }
}

class _AccountsOverview extends StatelessWidget {
  final AppStore store;
  final DateTime month;
  const _AccountsOverview({required this.store, required this.month});

  @override
  Widget build(BuildContext context) {
    if (store.myAccounts.isEmpty) {
      return const Text(
        'Accounts and cards are detected automatically from '
        'your bank messages.',
      );
    }
    final byBank = <String, List<Account>>{};
    for (final a in store.myAccounts) {
      byBank.putIfAbsent(a.bank, () => []).add(a);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('🏦 ${store.banks.length} banks')),
            Chip(label: Text('💳 ${store.cardCount} cards')),
            Chip(label: Text('📒 ${store.bankAccountCount} accounts')),
          ],
        ),
        const SizedBox(height: 8),
        for (final e in byBank.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(e.key, style: Theme.of(context).textTheme.labelLarge),
          ),
          for (final a in e.value)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_iconFor(a.type), color: Royal.gold),
              title: Text(a.displayName),
              // The auto name already says type + last digits; only
              // repeat them when the user has given a custom name.
              subtitle: a.nickname.isEmpty
                  ? null
                  : Text(
                      '${a.type.label}'
                      '${a.last4.isEmpty ? '' : ' ••${a.last4}'}',
                    ),
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

class _MerchantReview extends StatelessWidget {
  final AppStore store;
  const _MerchantReview({required this.store});

  @override
  Widget build(BuildContext context) {
    final list = store.merchantsToReview();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'You pay these often, but I can\'t tell what they are. '
          'Tell me once and I\'ll categorise them from now on.',
        ),
        const SizedBox(height: 8),
        for (final m in list.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Royal.purple,
              foregroundColor: Royal.goldLight,
              child: Icon(Icons.storefront_outlined),
            ),
            title: Text(m.label, overflow: TextOverflow.ellipsis),
            subtitle: Text(describeSuggestion(m)),
            trailing: FilledButton.tonal(
              onPressed: () => showMerchantSheet(
                context,
                counterparty: m.label,
                summary: describeSuggestion(m),
              ),
              child: const Text('Tell me'),
            ),
          ),
      ],
    );
  }
}

class _SipOverview extends StatelessWidget {
  final AppStore store;
  final DateTime month;
  const _SipOverview({required this.store, required this.month});

  @override
  Widget build(BuildContext context) {
    final year = store.sipsInYear(month.year);
    final thisMonth = year.where((t) => t.date.month == month.month).toList();
    // One row per fund (merchant), with this month's total.
    final byFund = <String, (double, int)>{};
    for (final t in thisMonth) {
      final name = store.sipFundName(t);
      final cur = byFund[name] ?? (0.0, 0);
      byFund[name] = (cur.$1 + t.amount, cur.$2 + 1);
    }
    final yearTotal = year.fold(0.0, (s, t) => s + t.amount);
    final monthTotal = thisMonth.fold(0.0, (s, t) => s + t.amount);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This month', style: t.labelMedium),
                  Text(
                    money(monthTotal),
                    style: t.titleLarge?.copyWith(color: Royal.income(context)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('So far in ${month.year}', style: t.labelMedium),
                  Text(money(yearTotal), style: t.titleLarge),
                ],
              ),
            ),
          ],
        ),
        if (byFund.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('No SIP payments this month yet.'),
          )
        else ...[
          const SizedBox(height: 8),
          for (final e in byFund.entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Text('📈', style: TextStyle(fontSize: 20)),
              title: Text(e.key, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${e.value.$2} payment${e.value.$2 == 1 ? '' : 's'}',
              ),
              trailing: Text(
                money(e.value.$1),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
        const SizedBox(height: 4),
        Text('SIPs are counted as Invested, not Spent.', style: t.bodySmall),
      ],
    );
  }
}

class _DebtsOverview extends StatelessWidget {
  final AppStore store;
  const _DebtsOverview({required this.store});

  @override
  Widget build(BuildContext context) {
    final people = store.personBalances();
    if (people.isEmpty) {
      return const Text(
        'Nothing pending. Use Lend / Borrow in Chat to '
        'track money with friends.',
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'You\'ll get ${money(store.totalToReceive)}',
                style: TextStyle(
                  color: Royal.income(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              'You owe ${money(store.totalToPay)}',
              style: TextStyle(
                color: Royal.spend(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const Divider(),
        for (final p in people)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Royal.purple,
              foregroundColor: Royal.goldLight,
              child: Text(p.person.isEmpty ? '?' : p.person[0].toUpperCase()),
            ),
            title: Text(p.person),
            trailing: Text(
              p.amount > 0
                  ? 'owes you ${money(p.amount)}'
                  : 'you owe ${money(-p.amount)}',
              style: TextStyle(
                color: p.amount > 0
                    ? Royal.income(context)
                    : Royal.spend(context),
              ),
            ),
          ),
      ],
    );
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
    return Column(
      children: [
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
      ],
    );
  }
}
