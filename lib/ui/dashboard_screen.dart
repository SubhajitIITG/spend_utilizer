import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../services/categories.dart';
import '../util/format.dart';
import '../util/period.dart';
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
  /// The period everything on the Dashboard shows. Starts as this month.
  Period _period = Period.month(DateTime.now());
  TxnType _breakdown = TxnType.debit;

  void _shift(int delta) =>
      setState(() => _period = _period.shiftMonths(delta));

  Future<void> _choosePeriod() async {
    final picked = await pickPeriod(context, current: _period);
    if (picked != null) setState(() => _period = picked);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    final isCurrent =
        _period.isMonth &&
        _period.from.year == now.year &&
        _period.from.month == now.month;

    return Scaffold(
      appBar: royalAppBar(
        'Dashboard',
        actions: [
          const SyncStatusButton(),
          IconButton(
            tooltip: 'Choose dates',
            icon: const Icon(Icons.date_range_outlined),
            onPressed: _choosePeriod,
          ),
          IconButton(
            tooltip: 'Download statement (Excel or PDF)',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => exportStatement(context, initial: _period),
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
                period: _period,
                onPrev: _period.isMonth ? () => _shift(-1) : null,
                onNext: _period.isMonth && !isCurrent ? () => _shift(1) : null,
                onChoose: _choosePeriod,
                onReset: _period.isMonth
                    ? null
                    : () => setState(() => _period = Period.month(now)),
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
                  totals: store.categoryTotalsDuring(_period, _breakdown),
                ),
              ),
              // Investments right below the chart.
              if (store.investmentsDuring(_period).isNotEmpty ||
                  store.investmentsInYear(_period.to.year).isNotEmpty)
                _Section(
                  title: 'Investments',
                  child: _InvestmentsOverview(store: store, period: _period),
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
                child: _AccountsOverview(store: store, period: _period),
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
  final Period period;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onChoose;

  /// Back to the monthly view (null while showing a month).
  final VoidCallback? onReset;
  const _HeroCard({
    required this.store,
    required this.period,
    required this.onPrev,
    required this.onNext,
    required this.onChoose,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final spent = store.spentDuring(period);
    final recv = store.receivedDuring(period);
    final invested = store.investedDuring(period);
    // What's left after spending and investing.
    final net = recv - spent - invested;
    final count = store.txnsIn(period).length;
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
                // Tap the dates to choose another period.
                child: InkWell(
                  onTap: onChoose,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                period.label.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Royal.goldLight,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: Royal.goldLight,
                            ),
                          ],
                        ),
                        if (onReset != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: onReset,
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Back to monthly view'),
                          ),
                      ],
                    ),
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
  final Period period;
  const _AccountsOverview({required this.store, required this.period});

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
              trailing: Text(
                '${money(store.accountSpentDuring(a, period))} spent',
              ),
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

class _InvestmentsOverview extends StatelessWidget {
  final AppStore store;
  final Period period;
  const _InvestmentsOverview({required this.store, required this.period});

  @override
  Widget build(BuildContext context) {
    // "year" = the calendar year the period ends in, for context.
    final yearNo = period.to.year;
    final year = store.investmentsInYear(yearNo);
    final thisMonth = store.investmentsDuring(period);
    final periodLabel = period.isMonth ? 'This month' : 'This period';
    double sum(Iterable<Txn> ts) => ts.fold(0.0, (s, t) => s + t.amount);
    final t = Theme.of(context).textTheme;

    // SIP funds this month, grouped by fund.
    final funds = <String, double>{};
    for (final x in thisMonth.where((x) => x.category == sipCategory)) {
      final name = store.sipFundName(x);
      funds[name] = (funds[name] ?? 0) + x.amount;
    }

    Widget figure(String label, double v, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelMedium),
          Text(money(v), style: t.titleLarge?.copyWith(color: color)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            figure(periodLabel, sum(thisMonth), color: Royal.income(context)),
            figure('So far in $yearNo', sum(year)),
          ],
        ),
        const SizedBox(height: 8),
        // One row per investment type used this year.
        for (final cat in investmentCategoryOrder)
          if (year.any((x) => x.category == cat)) ...[
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(
                emojiFor(cat),
                style: const TextStyle(fontSize: 20),
              ),
              title: Text(
                cat == otherInvestCategory ? 'Other investments' : cat,
              ),
              subtitle: Text(
                '${money(sum(year.where((x) => x.category == cat)))} '
                'in $yearNo',
              ),
              trailing: Text(
                money(sum(thisMonth.where((x) => x.category == cat))),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (cat == sipCategory)
              for (final f in funds.entries)
                Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.key,
                          style: t.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(money(f.value), style: t.bodySmall),
                    ],
                  ),
                ),
          ],
        const SizedBox(height: 4),
        Text(
          'Right column: ${periodLabel.toLowerCase()}. Investments are '
          'counted as Invested, '
          'not Spent.',
          style: t.bodySmall,
        ),
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
