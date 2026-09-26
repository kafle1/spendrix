import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'entry_form.dart';

enum _Filter {
  all('All'),
  out('Money out'),
  income('Money in'),
  transfer('Transfers'),
  people('People');

  const _Filter(this.label);
  final String label;
}

/// one row of the flattened, grouped list
class _Day {
  const _Day(this.date, this.total);
  final DateTime date;
  final int total;
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.category, this.account, this.month});

  /// optional starting filters, used when opened from Insights or an account
  final String? category, account;
  final DateTime? month;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _searchCtrl = TextEditingController();
  var _filter = _Filter.all;
  String? _category, _account;
  DateTime? _month;

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    _account = widget.account;
    _month = widget.month;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _filter = _Filter.all;
    _category = null;
    _account = null;
    _month = null;
    _searchCtrl.clear();
  });

  bool _matchesKind(Entry e) => switch (_filter) {
    _Filter.all => true,
    _Filter.out => e.kind == Kind.expense,
    _Filter.income => e.kind == Kind.income,
    _Filter.transfer => e.kind == Kind.transfer,
    _Filter.people => e.kind == Kind.gave || e.kind == Kind.got,
  };

  String _haystack(Store store, Entry e) => [
    e.note,
    store.category(e.category)?.name ?? '',
    store.account(e.account)?.name ?? '',
    store.person(e.person)?.name ?? '',
    (e.amount / 100).toStringAsFixed(2),
  ].join(' ').toLowerCase();

  Future<void> _actions(Entry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate'),
              onTap: () => Navigator.pop(context, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'duplicate':
        // a fresh id makes it a draft the user still has to confirm
        openEntry(
          context,
          entry: entry.copyWith(id: newId(), date: DateTime.now()),
        );
      case 'delete':
        removeWithUndo(context, [entry], 'Deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final pushed = Navigator.canPop(context);
    final q = _searchCtrl.text.trim().toLowerCase();
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final filtered = [
      for (final e in store.entries)
        if (_matchesKind(e) &&
            (_category == null || e.category == _category) &&
            (_account == null || e.account == _account || e.to == _account) &&
            (_month == null || (e.date.year == _month!.year && e.date.month == _month!.month)) &&
            (q.isEmpty || _haystack(store, e).contains(q)))
          e,
    ];

    final groups = <DateTime, List<Entry>>{};
    for (final e in filtered) {
      (groups[dayOf(e.date)] ??= []).add(e);
    }
    final rows = <Object>[];
    for (final g in groups.entries) {
      rows.add(_Day(g.key, g.value.fold(0, (s, e) => s + e.signed)));
      rows.addAll(g.value);
    }

    var moneyIn = 0, moneyOut = 0;
    for (final e in filtered) {
      if (e.kind == Kind.income || e.kind == Kind.got) moneyIn += e.amount;
      if (e.kind == Kind.expense || e.kind == Kind.gave) moneyOut += e.amount;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: SafeArea(
        child: Narrow(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                            onPressed: () => setState(_searchCtrl.clear),
                          ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    for (final f in _Filter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                    if (_category != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          label: Text(store.category(_category)?.name ?? 'Uncategorized'),
                          onDeleted: () => setState(() => _category = null),
                        ),
                      ),
                    if (_account != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          label: Text(store.account(_account)?.name ?? 'Deleted account'),
                          onDeleted: () => setState(() => _account = null),
                        ),
                      ),
                    if (_month != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          label: Text(monthLabel(_month!)),
                          onDeleted: () => setState(() => _month = null),
                        ),
                      ),
                  ],
                ),
              ),
              if (store.entries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${filtered.length} ${filtered.length == 1 ? 'entry' : 'entries'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                        ),
                      ),
                      const Spacer(),
                      Flexible(child: Money(moneyIn, colored: true, style: t.bodySmall)),
                      const SizedBox(width: 12),
                      Flexible(child: Money(-moneyOut, colored: true, style: t.bodySmall)),
                    ],
                  ),
                ),
              Expanded(
                child: store.entries.isEmpty
                    ? Empty(
                        icon: Icons.receipt_long_outlined,
                        title: 'Nothing here yet',
                        body: 'Add your first entry to see it here.',
                        action: FilledButton.icon(
                          onPressed: () => openEntry(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Add'),
                        ),
                      )
                    : filtered.isEmpty
                    ? Empty(
                        icon: Icons.search_off,
                        title: 'No matches',
                        body: 'Try a different search or filter.',
                        action: OutlinedButton(onPressed: _clearFilters, child: const Text('Clear filters')),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          if (row is _Day) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(dayLabel(row.date), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                                  Money(row.total, colored: true, style: t.labelLarge),
                                ],
                              ),
                            );
                          }
                          final entry = row as Entry;
                          return Dismissible(
                            key: ValueKey(entry.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: c.error,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Delete', style: TextStyle(color: c.onError)),
                                  const SizedBox(width: 8),
                                  Icon(Icons.delete_outline, color: c.onError),
                                ],
                              ),
                            ),
                            onDismissed: (_) => removeWithUndo(context, [entry], 'Deleted'),
                            child: GestureDetector(onLongPress: () => _actions(entry), child: EntryTile(entry)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: pushed
          ? null
          : FloatingActionButton.extended(
              onPressed: () => openEntry(context),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
    );
  }
}
