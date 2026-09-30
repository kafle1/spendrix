import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'stats.dart';
import 'store.dart';
import 'theme.dart';
import 'update.dart';
import 'widgets.dart';

/// The old data is on the phone but couldn't be read. Cleared by a later run that works.
final legacyFailed = ValueNotifier(false);

/// The release file to install when the other Android app id still holds the old data.
final otherApp = ValueNotifier<String?>(null);

bool _running = false;

/// [importLegacy] that never throws, so startup always gets to the app.
Future<void> runLegacyImport(Store store) async {
  if (_running) return;
  _running = true;
  try {
    await importLegacy(store);
    legacyFailed.value = false;
  } catch (e, s) {
    // the old file stays in place, so nothing is lost and the next run tries again
    debugPrint('old data import failed: $e');
    trackError(e, s);
    legacyFailed.value = true;
  } finally {
    _running = false;
  }
}

/// Spendrix 1.x kept everything in sqlite. The first launch after the update copies it into
/// the store, then renames the file. It's never deleted, so a failed run just retries next launch.
Future<void> importLegacy(Store store) async {
  if (kIsWeb || !Platform.isAndroid) return;
  final path = '${await getDatabasesPath()}/expense_tracker.db';
  if (!File(path).existsSync()) return;
  // killed after saving but before the rename, a second import would undo edits made since
  // the v1- ids also catch a lost prefs file, where legacy.done and the dev id are gone
  if (prefs.getBool('legacy.done') != true && !store.ids.any((id) => id.startsWith('v1-'))) {
    // read-write on purpose, sqlite has to replay the journal the old app left when it was killed
    final db = await openDatabase(path, singleInstance: false);
    final List<Model> models;
    try {
      models = await _read(db, store);
    } finally {
      await db.close();
    }
    if (models.isNotEmpty) await store.saveAll(models);
    if (prefs.getString('theme') == null) {
      final dark = (await SharedPreferences.getInstance()).getBool('isDarkMode');
      if (dark != null) await setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    }
    await prefs.setBool('legacy.done', true);
  }
  await File(path).rename('$path.imported');
}

/// Erase all also removes the old app's copy kept after the import.
Future<void> dropLegacy() async {
  if (kIsWeb || !Platform.isAndroid) return;
  final f = File('${await getDatabasesPath()}/expense_tracker.db.imported');
  if (f.existsSync()) await f.delete();
}

/// Android: 1.2 and older installed as com.example.expenses_tracker, 1.3 to 2.0.1 as com.spendrix.
/// A first install of the wrong file sits next to the old app and can't see its data.
Future<void> checkOtherApp() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    final me = (await PackageInfo.fromPlatform()).packageName;
    final other = me == 'com.spendrix' ? 'com.example.expenses_tracker' : 'com.spendrix';
    if (await const MethodChannel('spendrix/apps').invokeMethod<bool>('installed', other) == true) {
      otherApp.value = other == 'com.spendrix' ? 'Spendrix-android-for-1.3-and-2.0.apk' : 'Spendrix-android.apk';
    }
  } catch (e) {
    debugPrint('other app check failed: $e');
  }
}

/// Welcome page and Home: old data this copy can't show yet.
class OldDataCard extends StatelessWidget {
  const OldDataCard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([legacyFailed, otherApp]),
    builder: (context, _) {
      final store = context.watch<Store>();
      if (legacyFailed.value) {
        return _card(
          Icons.history,
          "Couldn't bring over your old data",
          "It's still safe on this phone, so don't uninstall Spendrix. Tap to try again.",
          () async {
            await runLegacyImport(store);
            if (context.mounted) toast(context, legacyFailed.value ? 'Still not working. Your old data is untouched.' : 'Your old data is back');
          },
        );
      }
      final file = otherApp.value;
      if (file != null && store.entries.isEmpty) {
        return _card(
          Icons.phone_android,
          'Your old Spendrix is still on this phone',
          "This copy can't see its data. Tap to get the right file and install it, then remove this empty copy.",
          () async {
            final url = 'https://github.com/kafle1/spendrix/releases/latest/download/$file';
            if (!await openUpdate(url) && context.mounted) toast(context, "Couldn't open the browser");
          },
        );
      }
      return const SizedBox.shrink();
    },
  );

  Widget _card(IconData icon, String title, String subtitle, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(subtitle), onTap: onTap),
    ),
  );
}

const _kinds = {
  'expense': Kind.expense,
  'income': Kind.income,
  'lend_given': Kind.gave,
  'lend_returned_expense': Kind.gave,
  'lend_taken': Kind.got,
  'lend_returned_income': Kind.got,
};

Future<List<Model>> _read(Database db, Store store) async {
  final tables = {for (final r in await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")) r['name']};
  Future<List<Map<String, Object?>>> rows(String t) async => tables.contains(t) ? db.query(t, orderBy: 'id') : [];
  final accRows = await rows('accounts'), catRows = await rows('categories'), txRows = await rows('transactions');
  final lendRows = await rows('lend_records'), limitRows = await rows('spending_limits');
  if (accRows.isEmpty && catRows.isEmpty && txRows.isEmpty && lendRows.isEmpty) return [];

  // ids carry this device's id, so two old phones syncing into one account never overwrite each other
  final p = 'v1-${store.dev}';
  final accIds = {for (final r in accRows) r['id']: '$p-acc-${r['id']}'};
  final catIds = {for (final r in catRows) r['id']: '$p-cat-${r['id']}'};
  // old balances are current balances, entries get subtracted below to find each account's start
  final start = {for (final r in accRows) accIds[r['id']]!: _cents(r['balance'])};
  String? old;
  final people = <String, Person>{};
  String? person(Object? raw) {
    final name = _str(raw);
    if (name.isEmpty) return null;
    return (people[name.toLowerCase()] ??= Person(id: '$p-person-${people.length}', name: name)).id;
  }

  final entries = <Entry>[];
  for (final r in txRows) {
    final kind = _kinds[_str(r['type'])];
    if (kind == null) continue;
    final lend = kind == Kind.gave || kind == Kind.got;
    entries.add(
      Entry(
        id: '$p-tx-${r['id']}',
        kind: kind,
        amount: _cents(r['amount']).abs(),
        date: _date(r['date'], r['createdAt']),
        // 1.x deleted accounts but kept their entries
        account: accIds[r['accountId']] ?? (old ??= '$p-acc-old'),
        category: lend ? null : catIds[r['categoryId']],
        person: lend ? person(r['personName']) ?? person('Someone') : null,
        note: _str(r['remarks']),
      ),
    );
  }
  // 1.x lend records never touched an account, so they sit on a hidden one with a zero balance
  for (final r in lendRows) {
    final kind = switch (_str(r['type'])) {
      'given' => Kind.gave,
      'taken' => Kind.got,
      _ => null,
    };
    if (kind == null) continue;
    final e = Entry(
      id: '$p-lend-${r['id']}',
      kind: kind,
      amount: _cents(r['amount']).abs(),
      date: _date(r['date'], r['createdAt']),
      account: old ??= '$p-acc-old',
      person: person(r['personName']) ?? person('Someone'),
      note: _str(r['remarks']),
    );
    entries.add(e);
    if (_num(r['isSettled']) != 0) {
      entries.add(
        Entry(
          id: '${e.id}-settled',
          kind: kind == Kind.gave ? Kind.got : Kind.gave,
          amount: e.amount,
          date: e.date,
          account: e.account,
          person: e.person,
          note: 'Settled',
        ),
      );
    }
  }
  for (final e in entries) {
    start[e.account] = (start[e.account] ?? 0) - e.signed;
  }

  int? overall;
  final budgets = <String, int>{};
  for (final r in limitRows) {
    final end = DateTime.tryParse(_str(r['endDate']));
    if (_num(r['isActive']) == 0 || (end != null && end.isBefore(DateTime.now()))) continue;
    final amount = _num(r['limitAmount']).abs();
    final monthly = switch (_str(r['period'])) {
      'daily' => amount * 365 / 12,
      'weekly' => amount * 52 / 12,
      'yearly' => amount / 12,
      'custom' when end != null => amount * 365 / 12 / max(1, end.difference(_date(r['startDate'], null)).inDays + 1),
      _ => amount,
    };
    final cents = (monthly * 100).round();
    if (cents <= 0) continue;
    final cats = {for (final s in _str(r['categoryIds']).split(',')) ?catIds[int.tryParse(s.trim())]};
    // the new app has one budget per category or one overall, so a limit on a few categories becomes overall
    if (cats.length == 1) {
      budgets.update(cats.first, (b) => min(b, cents), ifAbsent: () => cents);
    } else {
      overall = min(overall ?? cents, cents);
    }
  }

  final accounts = [
    for (final r in accRows)
      Account(
        id: accIds[r['id']]!,
        name: _str(r['name'], 'Account'),
        icon: _icon('${_str(r['name'])} ${_str(r['type'])}', 'wallet'),
        start: start[accIds[r['id']]]!,
      ),
    if (old != null) Account(id: old, name: 'Old records', icon: 'other', start: start[old]!, archived: true),
  ];
  return [
    if (!store.onboarded) Settings(currency: 'NPR', budget: overall),
    ...accounts,
    if (store.accounts.isEmpty && accounts.every((a) => a.archived)) defaults.first,
    for (final r in catRows)
      Category(
        id: catIds[r['id']]!,
        name: _str(r['name'], 'Other'),
        icon: _icon(_str(r['name']), 'other'),
        income: _str(r['type']) == 'income',
        budget: budgets[catIds[r['id']]],
      ),
    ...people.values,
    ...entries,
  ];
}

double _num(Object? v) {
  final d = v is num ? v.toDouble() : double.tryParse('$v');
  return d != null && d.isFinite ? d : 0;
}

int _cents(Object? v) => (_num(v) * 100).round();

String _str(Object? v, [String empty = '']) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? empty : s;
}

DateTime _date(Object? v, Object? fallback) =>
    DateTime.tryParse(_str(v)) ?? DateTime.tryParse(_str(fallback)) ?? DateTime.now();

// 1.x never stored icons, so guess one from the name
final _hints = {
  r'bank|nabil|nic|global|sanima|laxmi': 'bank',
  r'cash': 'cash',
  r'card|credit': 'card',
  r'esewa|khalti|fonepay|ime|mobile|phone': 'phone',
  r'saving': 'savings',
  r'wallet': 'wallet',
  r'food|khana|meal|lunch|dinner|breakfast|restaurant|snack|momo': 'food',
  r'grocer|vegetable|tarkari|market|kirana': 'groceries',
  r'tea|coffee|chiya|cafe': 'coffee',
  r'transport|bus|taxi|bike|ride|pathao|indrive': 'transport',
  r'fuel|petrol|diesel': 'fuel',
  r'travel|trip|tour|hotel|flight': 'travel',
  r'bill|electric|bijuli|water|gas': 'bills',
  r'internet|wifi|recharge|data': 'internet',
  r'shop': 'shopping',
  r'cloth|dress|shoe': 'clothes',
  r'health|medic|hospital|doctor|pharma': 'health',
  r'beauty|salon|hair|cosmetic': 'beauty',
  r'movie|fun|entertain|party|game': 'fun',
  r'sport|gym|fitness': 'sports',
  r'educat|school|college|tuition|book|course|fee': 'education',
  r'kid|child|baby': 'kids',
  r'pets?\b|dog|cat\b': 'pets',
  r'rent|home|house|room|kotha': 'home',
  r'repair|maintenance': 'repair',
  r'insurance': 'insurance',
  r'tax': 'tax',
  r'donat|charity|temple|puja': 'charity',
  r'subscri|netflix|spotify|youtube': 'subscriptions',
  r'salary|wage|talab': 'salary',
  r'business|sale|profit': 'business',
  r'gift': 'gift',
  r'invest|interest|stock|share|dividend': 'investment',
}.entries.map((e) => (RegExp('\\b(?:${e.key})', caseSensitive: false), e.value)).toList();

String _icon(String name, String fallback) {
  for (final (re, icon) in _hints) {
    if (re.hasMatch(name)) return icon;
  }
  return fallback;
}
