import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'entry_form.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final people = store.people;

    if (people.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('People')),
        body: Empty(
          icon: Icons.people_outline,
          title: 'No people yet',
          body: 'Add someone to track money you gave or got.',
          action: FilledButton.icon(
            onPressed: () => editPerson(context),
            icon: const Icon(Icons.add),
            label: const Text('Add person'),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => editPerson(context),
          tooltip: 'Add person',
          child: const Icon(Icons.add),
        ),
      );
    }

    var youGet = 0, youGive = 0;
    for (final p in people) {
      final o = store.owed(p.id);
      if (o > 0) youGet += o;
      if (o < 0) youGive += -o;
    }
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? people
        : [
            for (final p in people)
              if (p.name.toLowerCase().contains(q)) p,
          ];

    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: Narrow(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      statColumn(
                        context,
                        "You'll get",
                        Money(youGet, colored: true),
                        valueStyle: Theme.of(context).textTheme.titleLarge,
                      ),
                      statColumn(
                        context,
                        "You'll give",
                        Money(-youGive, colored: true),
                        valueStyle: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (people.length > 8)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search people'),
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text('No one matches "${_search.text.trim()}"'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _personRow(context, store, filtered[i]),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => editPerson(context),
        tooltip: 'Add person',
        child: const Icon(Icons.add),
      ),
    );
  }
}

Widget _personRow(BuildContext context, Store store, Person p) => ListTile(
  leading: const IconBubble(Icons.person_outline),
  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
  subtitle: p.phone == null ? null : Text(p.phone!, maxLines: 1, overflow: TextOverflow.ellipsis),
  trailing: Money(store.owed(p.id), colored: true, style: Theme.of(context).textTheme.titleMedium),
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      settings: const RouteSettings(name: 'person'),
      builder: (_) => PersonScreen(personId: p.id),
    ),
  ),
);

class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final person = store.person(personId);

    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Person')),
        body: const Empty(icon: Icons.person_off_outlined, title: 'This person was deleted'),
      );
    }

    final owed = store.owed(personId);
    final history = [
      for (final e in store.entries)
        if (e.person == personId) e,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                await editPerson(context, person);
                return;
              }
              if (v == 'delete' && context.mounted) {
                final ok = await confirm(
                  context,
                  title: 'Delete ${person.name}?',
                  body: history.isEmpty
                      ? null
                      : 'Their ${history.length == 1 ? 'entry' : '${history.length} entries'} will be deleted too.',
                  action: 'Delete',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                final nav = Navigator.of(context);
                await removeWithUndo(context, [
                  person,
                  ...history,
                  ...store.recurring.where((r) => r.person == personId),
                ], 'Person deleted');
                nav.pop();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: Narrow(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(
                children: [
                  const IconBubble(Icons.person_outline, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    owed == 0
                        ? 'All settled up'
                        : owed > 0
                        ? '${person.name} owes you'
                        : 'You owe ${person.name}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Money(owed, colored: true, style: Theme.of(context).textTheme.headlineMedium),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => openEntry(context, kind: Kind.gave, person: personId),
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('You gave'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => openEntry(context, kind: Kind.got, person: personId),
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('You got'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (owed != 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => openEntry(
                          context,
                          entry: Entry(
                            id: newId(),
                            kind: owed > 0 ? Kind.got : Kind.gave,
                            amount: owed.abs(),
                            date: DateTime.now(),
                            account: '',
                            person: personId,
                          ),
                        ),
                        child: const Text('Settle up'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(
                            text: owed > 0
                                ? '${person.name}, a friendly reminder that you owe me ${store.fmt(owed)}.'
                                : 'Hi ${person.name}, just a note that I owe you ${store.fmt(-owed)}. Settling up soon.',
                          ),
                        ),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Remind'),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: history.isEmpty
                  ? const Empty(icon: Icons.receipt_long_outlined, title: 'No history yet')
                  : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, i) => EntryTile(history[i], showDate: true),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add ([person] null) or edit a person. Returns the saved person, or null if cancelled.
Future<Person?> editPerson(BuildContext context, [Person? person]) async {
  final store = context.read<Store>();
  final nameCtrl = TextEditingController(text: person?.name ?? '');
  final phoneCtrl = TextEditingController(text: person?.phone ?? '');
  final formKey = GlobalKey<FormState>();

  void submit(BuildContext sheetContext) {
    if (formKey.currentState!.validate()) Navigator.pop(sheetContext, true);
  }

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
      child: Narrow(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(person == null ? 'Add person' : 'Edit person', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                onFieldSubmitted: (_) => submit(sheetContext),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => submit(sheetContext), child: const Text('Save')),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (saved != true) return null;
  final phone = phoneCtrl.text.trim();
  final result = Person(id: person?.id ?? newId(), name: nameCtrl.text.trim(), phone: phone.isEmpty ? null : phone);
  await store.save(result);
  return result;
}
