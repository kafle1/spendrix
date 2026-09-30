import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../sync.dart';
import '../legacy.dart';
import '../update.dart';
import '../widgets.dart';
import 'activity.dart';
import 'entry_form.dart';
import 'settings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final problem = context.watch<Sync>().problem;
    final showWarning = problem != null && problem.problem != Problem.offline;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final spent = store.spent(monthStart, nextMonth);

    var owedToYou = 0, youOwe = 0;
    for (final p in store.people) {
      final o = store.owed(p.id);
      if (o > 0) owedToYou += o;
      if (o < 0) youOwe -= o;
    }
    final showOwed = owedToYou != 0 || youOwe != 0;
    final hasEntries = store.entries.isNotEmpty;
    final recent = store.entries.take(6).toList();
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spendrix'),
        actions: [
          if (showWarning)
            IconButton(
              icon: Icon(Icons.warning_amber_rounded, color: c.error),
              tooltip: problem.message,
              onPressed: () => openSettings(context),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => openSettings(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Narrow(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ValueListenableBuilder(valueListenable: update, builder: (context, u, _) => _updateCard(context, u)),
              const OldDataCard(),
              Text('Total balance', style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
              const SizedBox(height: 4),
              Money(store.total, style: t.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              if (hasEntries) _monthCard(context, store, spent) else _firstRunCard(context),
              const SizedBox(height: 20),
              _accountsRow(context, store),
              if (showOwed) ...[const SizedBox(height: 16), _owedRow(context, store, owedToYou, youOwe)],
              if (hasEntries) ...[const SizedBox(height: 20), _recentSection(context, recent)],
              // asked once, after the first entry, so a brand-new user isn't hit with it on the first screen
              if (hasEntries)
                ValueListenableBuilder(
                  valueListenable: statsOn,
                  builder: (context, on, _) => on == null
                      ? Padding(padding: const EdgeInsets.only(top: 20), child: _statsCard(context))
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openEntry(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

Widget _monthCard(BuildContext context, Store store, int spent) {
  final budget = store.settings.budget;
  final over = budget != null && spent > budget;
  final c = Theme.of(context).colorScheme;
  final t = Theme.of(context).textTheme;
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spent this month', style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
          const SizedBox(height: 4),
          Money(spent, style: t.headlineSmall),
          if (budget != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (spent / budget).clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: c.surfaceContainerHighest,
                color: over ? c.error : c.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              over ? '${store.fmt(spent - budget)} over budget' : '${store.fmt(budget - spent)} left',
              style: t.bodyMedium?.copyWith(
                color: over ? c.error : c.onSurfaceVariant,
                fontWeight: over ? FontWeight.w600 : null,
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            TextButton(onPressed: () => openSettings(context), child: const Text('Set a monthly budget')),
          ],
        ],
      ),
    ),
  );
}

Widget _firstRunCard(BuildContext context) {
  final c = Theme.of(context).colorScheme;
  final t = Theme.of(context).textTheme;
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 40, color: c.primary),
          const SizedBox(height: 12),
          Text('Add your first entry', style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Use the + button below, snap a receipt in Ask, or turn on sync in Settings.',
            style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => openEntry(context), child: const Text('Add your first entry')),
        ],
      ),
    ),
  );
}

Widget _statsCard(BuildContext context) {
  final t = Theme.of(context).textTheme;
  return Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Help make Spendrix better?', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Share anonymous counts, like which screens get used and when something breaks. '
            'Never amounts, names or notes. You can change this in Settings.',
            style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton(onPressed: () => setStats(false), child: const Text('No thanks')),
              TextButton(onPressed: () => setStats(true), child: const Text('Share')),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _accountsRow(BuildContext context, Store store) {
  final c = Theme.of(context).colorScheme;
  // scrolls to content height instead of a fixed SizedBox, so 2x text scale can't overflow it
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in store.accounts)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _AccountCard(account: a, balance: store.balance(a.id)),
          ),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => editAccount(context),
          child: Container(
            width: 120,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: c.outlineVariant),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: c.primary),
                const SizedBox(height: 6),
                Text('Add account', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.balance});

  final Account account;
  final int balance;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'account'),
        builder: (_) => ActivityScreen(account: account.id),
      ),
    ),
    child: Container(
      width: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(iconOf(account.icon), size: 32),
          const SizedBox(height: 8),
          Text(
            account.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Money(balance, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

Widget _updateCard(BuildContext context, ({String version, String url})? u) => u == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: Text('Spendrix ${u.version} is out'),
            subtitle: const Text('Tap to download it, then open the file to install. Your data stays.'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Not now',
              onPressed: () => update.value = null,
            ),
            onTap: () async {
              if (!await openUpdate(u.url) && context.mounted) toast(context, "Couldn't open the browser");
            },
          ),
        ),
      );

Widget _owedRow(BuildContext context, Store store, int owedToYou, int youOwe) => Card(
  child: ListTile(
    leading: const Icon(Icons.people_outline),
    title: Text(
      'People owe you ${store.fmt(owedToYou)} · You owe ${store.fmt(youOwe)}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => currentTab.value = 4,
  ),
);

Widget _recentSection(BuildContext context, List<Entry> recent) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Recent', style: Theme.of(context).textTheme.titleMedium),
          TextButton(onPressed: () => currentTab.value = 1, child: const Text('See all')),
        ],
      ),
    ),
    Card(child: Column(children: [for (final e in recent) EntryTile(e, showDate: true)])),
  ],
);
