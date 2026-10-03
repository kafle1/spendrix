import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../stats.dart';
import '../store.dart';
import '../widgets.dart';
import 'activity.dart';
import 'entry_form.dart';
import 'settings.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month);
DateTime _addMonths(DateTime d, int n) => DateTime(d.year, d.month + n);

class _InsightsScreenState extends State<InsightsScreen> {
  late DateTime _month = _startOfMonth(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final from = _month;
    final to = _addMonths(_month, 1);
    final earned = store.earned(from, to);
    final spent = store.spent(from, to);
    final empty = earned == 0 && spent == 0;
    final atLatest = !_month.isBefore(_startOfMonth(DateTime.now()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          if (!empty)
            IconButton(
              onPressed: () => _share(store, from, to),
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share this month',
            ),
        ],
      ),
      body: Narrow(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => setState(() => _month = _addMonths(_month, -1)),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous month',
                  ),
                  SizedBox(
                    width: 160,
                    child: Text(
                      monthLabel(_month),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: atLatest ? null : () => setState(() => _month = _addMonths(_month, 1)),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next month',
                  ),
                ],
              ),
            ),
            Expanded(
              child: empty
                  ? Empty(
                      icon: Icons.insights_outlined,
                      title: 'Nothing this month yet',
                      body: 'Add some money in or out to see it here.',
                      action: FilledButton.icon(
                        onPressed: () => openEntry(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              statColumn(context, 'Money in', Money(earned, colored: true)),
                              statColumn(context, 'Money out', Money(-spent, colored: true)),
                              statColumn(context, "What's left", Money(earned - spent, colored: true)),
                            ],
                          ),
                        ),
                        if (spent > 0) ...[const SizedBox(height: 16), _donut(context, store, from, to, spent)],
                        ..._gap,
                        _budgets(context, store, from, to),
                        ..._gap,
                        _trend(context, store, _month),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The month as plain text, for WhatsApp, email and the like.
  void _share(Store store, DateTime from, DateTime to) {
    final earned = store.earned(from, to), spent = store.spent(from, to), budget = store.settings.budget;
    final title = 'My money in ${DateFormat('MMMM y').format(from)}';
    final text = StringBuffer('$title\n')
      ..writeln('Money in: ${store.fmt(earned)}')
      ..writeln('Money out: ${store.fmt(spent)}')
      ..writeln("What's left: ${store.fmt(earned - spent)}");
    if (budget != null) {
      text.writeln(
        spent > budget ? 'Budget: ${store.fmt(spent - budget)} over' : 'Budget: ${store.fmt(budget - spent)} left',
      );
    }
    final cats = store.byCategory(from, to);
    if (cats.isNotEmpty) {
      final rest = cats.skip(5).fold(0, (s, e) => s + e.value);
      text.writeln('\nWhere it went:');
      for (final e in cats.take(5)) {
        text.writeln('${store.category(e.key)?.name ?? 'Uncategorized'}: ${store.fmt(e.value)}');
      }
      if (rest > 0) text.writeln('Other: ${store.fmt(rest)}');
    }
    SharePlus.instance.share(ShareParams(text: text.toString().trim(), subject: title));
    track('feature_used', {'name': 'share_month'});
  }
}

/// colorblind-friendlier fixed palette (Okabe-Ito), legible on light and dark
const _palette = [Color(0xFF0072B2), Color(0xFFE69F00), Color(0xFF009E73), Color(0xFFCC79A7), Color(0xFF56B4E9)];
const _otherColor = Color(0xFF9E9E9E);

// sections are split by space and a thin line instead of boxes
const _gap = [SizedBox(height: 16), Divider(), SizedBox(height: 16)];

class _Slice {
  const _Slice(this.id, this.name, this.icon, this.amount, this.color);
  final String? id;
  final String name;
  final IconData icon;
  final int amount;
  final Color color;
}

Widget _donut(BuildContext context, Store store, DateTime from, DateTime to, int total) {
  final cats = store.byCategory(from, to);
  final top = cats.take(5).toList();
  final rest = cats.length > 5 ? cats.skip(5).fold(0, (s, e) => s + e.value) : 0;
  final slices = [
    for (final (i, e) in top.indexed)
      _Slice(
        e.key,
        store.category(e.key)?.name ?? 'Uncategorized',
        iconOf(store.category(e.key)?.icon),
        e.value,
        _palette[i % _palette.length],
      ),
    if (rest > 0) _Slice(null, 'Other', Icons.more_horiz, rest, _otherColor),
  ];

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader(context, 'Spending by category'),
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: [
                    for (final s in slices)
                      PieChartSectionData(value: s.amount.toDouble(), color: s.color, showTitle: false, radius: 28),
                  ],
                  centerSpaceRadius: 52,
                  sectionsSpace: 2,
                ),
              ),
              // big totals shrink to stay inside the ring's 104px hole
              SizedBox(
                width: 88,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    children: [
                      Text(store.fmt(total), style: Theme.of(context).textTheme.titleLarge),
                      Text('spent', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final s in slices) _legendRow(context, store, from, s, total),
      ],
    ),
  );
}

Widget _legendRow(BuildContext context, Store store, DateTime month, _Slice s, int total) {
  final pct = total == 0 ? 0 : (s.amount * 100 / total).round();
  return InkWell(
    // Other and Uncategorized have no single category to filter by
    onTap: s.id == null
        ? null
        : () => Navigator.push(
            context,
            MaterialPageRoute(
              settings: const RouteSettings(name: 'category'),
              builder: (_) => ActivityScreen(category: s.id, month: month),
            ),
          ),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // the slice colour ties the row to the ring
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          IconBubble(s.icon, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text('$pct%', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 12),
          Text(store.fmt(s.amount)),
        ],
      ),
    ),
  );
}

Widget _budgets(BuildContext context, Store store, DateTime from, DateTime to) {
  final catBudgets = [
    for (final c in store.categories)
      if (c.budget != null) c,
  ];
  final overall = store.settings.budget;
  if (overall == null && catBudgets.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Expanded(child: Text('Set budgets in Settings')),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: () => openSettings(context), child: const Text('Settings')),
        ],
      ),
    );
  }
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader(context, 'Budgets'),
        if (overall != null)
          _budgetBar(context, store, 'This month', Icons.calendar_month, store.spent(from, to), overall),
        for (final c in catBudgets) ...[
          const SizedBox(height: 12),
          _budgetBar(context, store, c.name, iconOf(c.icon), store.spent(from, to, category: c.id), c.budget!),
        ],
      ],
    ),
  );
}

Widget _budgetBar(BuildContext context, Store store, String label, IconData icon, int spent, int budget) {
  final left = budget - spent;
  final over = left < 0;
  final c = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 18, color: c.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Flexible(
            child: Text(
              over ? '${store.fmt(-left)} over' : '${store.fmt(left)} left',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: over ? c.error : c.onSurfaceVariant),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: (spent / budget).clamp(0, 1),
          minHeight: 6,
          backgroundColor: c.surfaceContainerHighest,
          color: over ? c.error : c.primary,
        ),
      ),
    ],
  );
}

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

Widget _trend(BuildContext context, Store store, DateTime month) {
  final points = [for (var i = 5; i >= 0; i--) _addMonths(month, -i)];
  final spentByMonth = [for (final m in points) store.spent(m, _addMonths(m, 1))];
  final maxSpent = spentByMonth.fold(0, (a, b) => a > b ? a : b);
  final c = Theme.of(context).colorScheme;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader(context, 'Money out, last 6 months'),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              maxY: maxSpent == 0 ? 100 : maxSpent * 1.2,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(_monthNames[points[i].month - 1], style: Theme.of(context).textTheme.bodySmall),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    store.fmt(rod.toY.round()),
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ),
              barGroups: [
                for (final (i, s) in spentByMonth.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: s.toDouble(),
                        width: 20,
                        borderRadius: BorderRadius.circular(6),
                        color: i == spentByMonth.length - 1 ? c.primary : c.primary.withValues(alpha: .35),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
