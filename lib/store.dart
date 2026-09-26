import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' hide Category;
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'format.dart';
import 'legacy.dart';
import 'models.dart';

/// device-only settings: theme, lock, sync session, device id
late final SharedPreferencesWithCache prefs;

String newId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Fixed ids, so two devices set up offline end up with one "Food", not two.
const defaults = <Model>[
  Account(id: 'acc-cash', name: 'Cash', icon: 'cash'),
  Category(id: 'cat-food', name: 'Food', icon: 'food'),
  Category(id: 'cat-groceries', name: 'Groceries', icon: 'groceries'),
  Category(id: 'cat-transport', name: 'Transport', icon: 'transport'),
  Category(id: 'cat-bills', name: 'Bills', icon: 'bills'),
  Category(id: 'cat-shopping', name: 'Shopping', icon: 'shopping'),
  Category(id: 'cat-health', name: 'Health', icon: 'health'),
  Category(id: 'cat-fun', name: 'Fun', icon: 'fun'),
  Category(id: 'cat-education', name: 'Education', icon: 'education'),
  Category(id: 'cat-home', name: 'Rent & home', icon: 'home'),
  Category(id: 'cat-other', name: 'Other', icon: 'other'),
  Category(id: 'cat-salary', name: 'Salary', icon: 'salary', income: true),
  Category(id: 'cat-business', name: 'Business', icon: 'business', income: true),
  Category(id: 'cat-gift', name: 'Gift', icon: 'gift', income: true),
  Category(id: 'cat-other-in', name: 'Other income', icon: 'savings', income: true),
];

/// Seeded records carry this version, so any real edit from any device beats them.
const _seeded = 1;

class Store extends ChangeNotifier {
  Store._(this._box, this._photos, this.dev);

  final Box<String> _box;
  final LazyBox<Uint8List> _photos;

  /// this device's id, stamped on every edit it makes
  final String dev;
  final _items = <String, Item>{};

  /// set by sync so a local edit gets pushed a few seconds later
  VoidCallback? onEdit;

  /// bumped on erase or wipe, so screens holding old data (the Ask chat) start over
  int resets = 0;

  static Future<Store> open() async {
    // app support dir, not Documents, so desktop users don't see a stray folder
    Hive.init(kIsWeb ? null : (await getApplicationSupportDirectory()).path);
    var dev = prefs.getString('dev');
    if (dev == null) await prefs.setString('dev', dev = newId());
    final s = Store._(await Hive.openBox<String>('items'), await Hive.openLazyBox<Uint8List>('photos'), dev);
    for (final raw in s._box.values) {
      try {
        final i = Item.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        s._items[i.id] = i;
      } catch (_) {
        // a row this build can't read is left alone rather than crashing the app
      }
    }
    s._index();
    await s._sweepPhotos();
    return s;
  }

  // ---- read side ----
  // ponytail: everything lives in memory and is re-indexed on each change;
  // fine to ~50k entries, move totals into incremental counters past that.

  Settings settings = const Settings(currency: 'NPR');
  List<Account> allAccounts = [];
  List<Category> categories = [];
  List<Person> people = [];

  /// newest first
  List<Entry> entries = [];
  List<Recurring> recurring = [];
  final _byId = <String, Model>{};
  final _balance = <String, int>{};
  final _owed = <String, int>{};

  bool get onboarded => _items['settings']?.deleted == false;
  Currency get currency => currencyOf(settings.currency);
  String fmt(int cents, {bool sign = false}) => money(cents, currency, sign: sign);

  /// home cents per cent of [code], from the newest entry paid in it; null when there's nothing to go on
  double? rate(String code) {
    for (final e in entries) {
      if (e.fx?.code == code) return e.amount / e.fxAmount!;
    }
    // the Indian rupee is pegged at 1.6 Nepali rupees
    return switch ((settings.currency, code)) {
      ('NPR', 'INR') => 1.6,
      ('INR', 'NPR') => 1 / 1.6,
      _ => null,
    };
  }

  List<Account> get accounts => [
    for (final a in allAccounts)
      if (!a.archived) a,
  ];
  List<Category> categoriesFor(Kind kind) => [
    for (final c in categories)
      if (c.income == (kind == Kind.income)) c,
  ];

  Account? account(String? id) => _byId[id] is Account ? _byId[id] as Account : null;
  Category? category(String? id) => _byId[id] is Category ? _byId[id] as Category : null;
  Person? person(String? id) => _byId[id] is Person ? _byId[id] as Person : null;
  Entry? entry(String? id) => _byId[id] is Entry ? _byId[id] as Entry : null;
  Recurring? recurringOf(String? id) => _byId[id] is Recurring ? _byId[id] as Recurring : null;

  /// where new money goes when nothing says otherwise: the last account used, else the first
  String? get defaultAccount {
    final last = prefs.getString('lastAccount');
    return accounts.any((a) => a.id == last) ? last : accounts.firstOrNull?.id;
  }

  /// the entry added or edited most recently; made-by-a-repeat ones carry their due date, so they don't count
  Entry? get lastTouched {
    Entry? best;
    for (final e in entries) {
      if (best == null || _items[e.id]!.updated > _items[best.id]!.updated) best = e;
    }
    return best;
  }

  int balance(String accountId) => _balance[accountId] ?? 0;
  int get total => accounts.fold(0, (sum, a) => sum + balance(a.id));

  /// above zero: they owe you. below zero: you owe them.
  int owed(String personId) => _owed[personId] ?? 0;

  /// money out (expense) between [from] inclusive and [to] exclusive
  int spent(DateTime from, DateTime to, {String? category}) => _sum(Kind.expense, from, to, category);

  /// money in (income) between [from] inclusive and [to] exclusive
  int earned(DateTime from, DateTime to) => _sum(Kind.income, from, to, null);

  int _sum(Kind kind, DateTime from, DateTime to, String? category) {
    var sum = 0;
    for (final e in entries) {
      if (e.kind == kind &&
          !e.date.isBefore(from) &&
          e.date.isBefore(to) &&
          (category == null || e.category == category)) {
        sum += e.amount;
      }
    }
    return sum;
  }

  /// spending per category id (null = no category) in a date range, biggest first
  List<MapEntry<String?, int>> byCategory(DateTime from, DateTime to) {
    final m = <String?, int>{};
    for (final e in entries) {
      if (e.kind == Kind.expense && !e.date.isBefore(from) && e.date.isBefore(to)) {
        m[e.category] = (m[e.category] ?? 0) + e.amount;
      }
    }
    return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  void _index() {
    final order = {for (final (i, d) in defaults.indexed) d.id: i};
    Settings? s;
    allAccounts = [];
    categories = [];
    people = [];
    entries = [];
    recurring = [];
    _byId.clear();
    for (final i in _items.values) {
      if (i.deleted) continue;
      final Model m;
      switch (i.type) {
        case 'settings':
          s = Settings.from(i);
          continue;
        case 'account':
          allAccounts.add(m = Account.from(i));
        case 'category':
          categories.add(m = Category.from(i));
        case 'person':
          people.add(m = Person.from(i));
        case 'entry':
          entries.add(m = Entry.from(i));
        case 'recurring':
          recurring.add(m = Recurring.from(i));
        default:
          continue;
      }
      _byId[m.id] = m;
    }
    settings = s ?? const Settings(currency: 'NPR');
    int rank(Model m) => order[m.id] ?? defaults.length;
    int byRank(Model a, Model b, String an, String bn) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : an.toLowerCase().compareTo(bn.toLowerCase());
    }

    allAccounts.sort((a, b) => byRank(a, b, a.name, b.name));
    categories.sort((a, b) => byRank(a, b, a.name, b.name));
    people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    recurring.sort((a, b) => a.note.compareTo(b.note));
    entries.sort((a, b) => b.date.compareTo(a.date));

    _balance
      ..clear()
      ..addAll({for (final a in allAccounts) a.id: a.start});
    _owed.clear();
    for (final e in entries) {
      if (e.kind == Kind.transfer) {
        _balance[e.account] = (_balance[e.account] ?? 0) - e.amount;
        if (e.to != null) _balance[e.to!] = (_balance[e.to!] ?? 0) + e.amount;
        continue;
      }
      _balance[e.account] = (_balance[e.account] ?? 0) + e.signed;
      if (e.person != null && (e.kind == Kind.gave || e.kind == Kind.got)) {
        _owed[e.person!] = (_owed[e.person!] ?? 0) - e.signed;
      }
    }
  }

  // ---- write side ----

  int _next(Item? prev) => max(DateTime.now().millisecondsSinceEpoch, (prev?.updated ?? 0) + 1);

  Item _edit(Model m) {
    final prev = _items[m.id];
    return Item(
      id: m.id,
      type: m.type,
      // unknown keys from a newer app version survive the save
      data: {...?prev?.data, ...m.toData().map((k, v) => MapEntry(k, _limit(k, v)))},
      updated: _next(prev),
      dev: dev,
      dirty: true,
    );
  }

  static Object? _limit(String key, Object? v) {
    if (v is! String) return v;
    final t = v.trim();
    final cap = key == 'note' ? 1000 : 100;
    return t.length > cap ? t.substring(0, cap) : t;
  }

  Future<void> save(Model m) async {
    await _putAll([_edit(m)]);
    if (m is Recurring) await runRecurring();
    onEdit?.call();
  }

  Future<void> saveAll(Iterable<Model> models) async {
    await _putAll([for (final m in models) _edit(m)]);
    onEdit?.call();
  }

  /// Deletes by leaving a tombstone, so the delete reaches other devices too.
  /// Undo is just saving the old model again.
  Future<void> remove(Iterable<String> ids) async {
    final out = <Item>[];
    for (final id in ids) {
      final prev = _items[id];
      if (prev == null || prev.deleted) continue;
      out.add(
        Item(id: id, type: prev.type, data: const {}, updated: _next(prev), dev: dev, deleted: true, dirty: true),
      );
    }
    if (out.isEmpty) return;
    await _putAll(out);
    onEdit?.call();
  }

  Future<void> _putAll(List<Item> items, {bool notify = true}) async {
    if (items.isEmpty) return;
    final before = {for (final i in items) i.id: _items[i.id]};
    for (final i in items) {
      _items[i.id] = i;
    }
    if (notify) {
      _index();
      notifyListeners();
    }
    try {
      await _box.putAll({for (final i in items) i.id: jsonEncode(i.toJson())});
    } catch (_) {
      // a failed write (disk full) must not leave memory ahead of disk, or the next pull skips the record
      for (final i in items) {
        if (!identical(_items[i.id], i)) continue;
        if (before[i.id] case final b?) {
          _items[i.id] = b;
        } else {
          _items.remove(i.id);
        }
      }
      _index();
      notifyListeners();
      rethrow;
    }
  }

  /// First run: the picked currency as a real edit, so it syncs, plus the starter set.
  Future<void> setup(String currency) async {
    await save(Settings(currency: currency));
    await _seed(settings);
  }

  Future<void> _seed(Settings s) => _putAll([
    for (final m in [s, ...defaults])
      if (_items[m.id] == null) Item(id: m.id, type: m.type, data: m.toData(), updated: _seeded, dev: dev),
  ]);

  /// Adds any due occurrences of repeating entries. The id is fixed per date, so a
  /// deleted occurrence stays deleted and two devices never make the same one twice.
  Future<void> runRecurring() async {
    await remove([
      for (final e in entries)
        if (_orphan(e)) e.id,
    ]);
    final today = DateTime.now();
    final out = <Item>[];
    for (final r in recurring) {
      if (!r.active || r.amount <= 0) continue;
      for (final d in r.dueUntil(today)) {
        final e = r.entryFor(d);
        if (_items.containsKey(e.id)) continue;
        // versioned at the due date so an edit made on another device still wins
        out.add(
          Item(id: e.id, type: e.type, data: e.toData(), updated: d.millisecondsSinceEpoch, dev: dev, dirty: true),
        );
      }
    }
    if (out.isEmpty) return;
    await _putAll(out);
    onEdit?.call();
  }

  /// An untouched occurrence this device made offline, dated after another device stopped or deleted its repeat.
  bool _orphan(Entry e) {
    final i = _items[e.id]!, r = _items[e.recurring];
    return r != null &&
        (r.deleted || r.data['active'] == false) &&
        i.dirty &&
        i.updated > r.updated &&
        i.updated == dayOf(e.date).millisecondsSinceEpoch;
  }

  /// Deletes every record everywhere, then puts the starter set back.
  Future<void> eraseAll() async {
    resets++;
    await remove([
      for (final i in _items.values)
        if (i.type != 'settings') i.id,
    ]);
    await saveAll(defaults);
    await _photos.clear();
    await dropLegacy();
    // hive only rewrites the file after ~60 deletes, so a small diary would stay readable on disk
    await _box.compact();
  }

  // ---- photos (kept on this device only) ----

  Future<Uint8List?> photo(String entryId) => _photos.get(entryId);

  Future<void> setPhoto(String entryId, Uint8List? bytes) =>
      bytes == null ? _photos.delete(entryId) : _photos.put(entryId, bytes);

  Future<void> _sweepPhotos() async {
    final dead = [
      for (final k in _photos.keys)
        if (entry(k as String)?.photo != true) k,
    ];
    await _photos.deleteAll(dead);
  }

  // ---- sync side ----

  Iterable<Item> get dirty => _items.values.where((i) => i.dirty);
  int get pending => dirty.length;

  /// true when this device holds anything beyond the starter set
  bool get hasOwnData => _items.values.any((i) => !i.deleted && i.updated > _seeded && i.type != 'settings');

  /// Applies copies pulled from the server. When ours is newer but clean, the server
  /// holds a stale copy, so ours is marked to be pushed again.
  Future<void> merge(List<Item> remote) async {
    final out = <Item>[];
    for (final r in remote) {
      final local = _items[r.id];
      if (local == null) {
        out.add(r);
      } else if (local.sameVersion(r)) {
        if (local.dirty) out.add(local.withDirty(false));
      } else if (r.beats(local) || (local.updated <= _seeded && !local.dirty)) {
        out.add(r.withDirty(false));
      } else if (!local.dirty) {
        out.add(local.withDirty(true));
      }
    }
    await _putAll(out);
  }

  /// Clears the dirty mark on items the server now holds, unless they changed again meanwhile.
  Future<void> markPushed(Iterable<Item> pushed) => _putAll([
    for (final p in pushed)
      if (_items[p.id] case final cur? when cur.dirty && cur.sameVersion(p)) cur.withDirty(false),
  ], notify: false);

  Future<void> markAllDirty() => _putAll([
    for (final i in _items.values)
      if (!i.dirty) i.withDirty(true),
  ]);

  /// Empties this device. With [keepSettings] the currency stays and the
  /// starter set is put back, ready to be filled from the account.
  Future<void> wipe({bool keepSettings = false}) async {
    final s = settings;
    resets++;
    await _box.clear();
    await _photos.clear();
    await dropLegacy();
    _items.clear();
    if (keepSettings) await _seed(s);
    _index();
    notifyListeners();
  }

  // ---- backup ----

  Future<Uint8List> backup() async {
    final photos = <String, String>{};
    for (final e in entries.where((e) => e.photo)) {
      final p = await _photos.get(e.id);
      if (p != null) photos[e.id] = base64Encode(p);
    }
    return utf8.encode(
      jsonEncode({
        'spendrix': 1,
        // deletes too, or a restore brings back deleted repeats and starter categories
        'items': [for (final i in _items.values) i.toJson(withDirty: false)],
        'photos': photos,
      }),
    );
  }

  /// Brings back every record in a backup file as a fresh edit, so it wins on
  /// every synced device too. Records made after the backup are kept.
  Future<int> restore(Uint8List bytes) async {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('This file is not a Spendrix backup.');
    }
    if (json is! Map || json['spendrix'] is! int || json['items'] is! List) {
      throw const FormatException('This file is not a Spendrix backup.');
    }
    const types = {'settings', 'account', 'category', 'person', 'entry', 'recurring'};
    final out = <Item>[];
    var live = 0;
    for (final raw in json['items'] as List) {
      // ids end up in file names and sync paths, so only the shapes the app itself makes get in
      if (raw is! Map ||
          raw['id'] is! String ||
          !RegExp(r'^[A-Za-z0-9-]{1,100}$').hasMatch(raw['id']) ||
          !types.contains(raw['type']) ||
          raw['data'] is! Map) {
        continue;
      }
      final id = raw['id'] as String, type = raw['type'] as String;
      final prev = _items[id];
      if (raw['deleted'] == true) {
        // a delete keeps its own time, so it never beats a record brought back after the backup
        final updated = raw['updated'], by = raw['dev'];
        if (updated is! num) continue;
        final gone = Item(
          id: id,
          type: type,
          data: const {},
          updated: updated.toInt(),
          dev: by is String ? by : '',
          deleted: true,
          dirty: true,
        );
        if (prev == null || gone.beats(prev)) out.add(gone);
        continue;
      }
      live++;
      out.add(
        Item(
          id: id,
          type: type,
          // capped like any edit, or one long note can push the record past the server's size limit
          data: (raw['data'] as Map<String, dynamic>).map((k, v) => MapEntry(k, _limit(k, v))),
          updated: _next(prev),
          dev: dev,
          dirty: true,
        ),
      );
    }
    final photos = json['photos'];
    if (photos is Map) {
      for (final MapEntry(:key, :value) in photos.entries) {
        if (key is String && value is String) {
          try {
            await _photos.put(key, base64Decode(value));
          } on FormatException {
            // skip one broken photo, keep the rest of the restore
          }
        }
      }
    }
    await _putAll(out);
    await runRecurring();
    onEdit?.call();
    return live;
  }

  String csv() {
    String cell(String s) {
      // a leading = + - @ would run as a formula in Excel
      final safe = RegExp(r'^[=+\-@]').hasMatch(s) ? "'$s" : s;
      return RegExp(r'[",\n\r]').hasMatch(safe) ? '"${safe.replaceAll('"', '""')}"' : safe;
    }

    final rows = ['Date,Type,Amount,Category,Account,To account,Person,Note,Paid in'];
    for (final e in entries) {
      final amount = (e.kind == Kind.transfer ? e.amount : e.signed) / 100;
      rows.add(
        [
          e.date.toIso8601String().substring(0, 10),
          e.kind.label,
          amount.toStringAsFixed(2),
          cell(category(e.category)?.name ?? ''),
          cell(account(e.account)?.name ?? ''),
          cell(account(e.to)?.name ?? ''),
          cell(person(e.person)?.name ?? ''),
          cell(e.note),
          if (e.fx case final fx?) '${fx.code} ${(e.fxAmount! / 100).toStringAsFixed(2)}' else '',
        ].join(','),
      );
    }
    return rows.join('\n');
  }
}
