import 'format.dart';

enum Kind {
  expense('Money out'),
  income('Money in'),
  transfer('Transfer'),
  gave('You gave'),
  got('You got');

  const Kind(this.label);
  final String label;

  /// effect on the account the money moves through; transfers are handled per side
  int get sign => this == income || this == got ? 1 : -1;

  static Kind parse(Object? name) => Kind.values.asNameMap()[name] ?? Kind.expense;
}

/// One stored record, the unit of both local storage and sync.
class Item {
  const Item({
    required this.id,
    required this.type,
    required this.data,
    required this.updated,
    required this.dev,
    this.deleted = false,
    this.dirty = false,
  });

  final String id, type, dev;
  final Map<String, dynamic> data;

  /// ms timestamp, only ever moves forward for a given id
  final int updated;
  final bool deleted, dirty;

  /// last writer wins; the device id breaks exact ties so every device picks the same copy
  bool beats(Item other) => updated != other.updated ? updated > other.updated : dev.compareTo(other.dev) > 0;

  bool sameVersion(Item other) => updated == other.updated && dev == other.dev;

  Item withDirty(bool value) =>
      Item(id: id, type: type, data: data, updated: updated, dev: dev, deleted: deleted, dirty: value);

  Map<String, dynamic> toJson({bool withDirty = true}) => {
    'id': id,
    'type': type,
    'data': data,
    'updated': updated,
    'dev': dev,
    if (deleted) 'deleted': true,
    if (withDirty && dirty) 'dirty': true,
  };

  static Item fromJson(Map<String, dynamic> j) => Item(
    id: j['id'] as String,
    type: j['type'] as String,
    data: Map<String, dynamic>.from(j['data'] as Map? ?? const {}),
    updated: (j['updated'] as num).toInt(),
    dev: j['dev'] as String? ?? '',
    deleted: j['deleted'] == true,
    dirty: j['dirty'] == true,
  );
}

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
String? _opt(Object? v) => v is String && v.isNotEmpty ? v : null;
int _int(Object? v) => v is num ? v.toInt() : 0;
DateTime _date(Object? v) => (v is String ? DateTime.tryParse(v) : null) ?? DateTime.now();

sealed class Model {
  const Model(this.id);
  final String id;
  String get type;
  Map<String, dynamic> toData();
}

class Settings extends Model {
  const Settings({required this.currency, this.budget}) : super('settings');
  final String currency;

  /// monthly spending limit in cents, null when not set
  final int? budget;

  @override
  String get type => 'settings';

  static Settings from(Item i) =>
      Settings(currency: _str(i.data['currency'], 'USD'), budget: _positive(i.data['budget']));

  @override
  Map<String, dynamic> toData() => {'currency': currency, 'budget': budget};
}

int? _positive(Object? v) => v is num && v > 0 ? v.toInt() : null;

class Account extends Model {
  const Account({required String id, required this.name, this.icon = 'cash', this.start = 0, this.archived = false})
    : super(id);
  final String name, icon;

  /// balance before the first entry, may be negative for a card
  final int start;
  final bool archived;

  @override
  String get type => 'account';

  static Account from(Item i) => Account(
    id: i.id,
    name: _str(i.data['name'], 'Account'),
    icon: _str(i.data['icon'], 'cash'),
    start: _int(i.data['start']),
    archived: i.data['archived'] == true,
  );

  @override
  Map<String, dynamic> toData() => {'name': name, 'icon': icon, 'start': start, 'archived': archived};
}

class Category extends Model {
  const Category({required String id, required this.name, required this.icon, this.income = false, this.budget})
    : super(id);
  final String name, icon;
  final bool income;

  /// monthly limit in cents for expense categories
  final int? budget;

  @override
  String get type => 'category';

  static Category from(Item i) => Category(
    id: i.id,
    name: _str(i.data['name'], 'Category'),
    icon: _str(i.data['icon'], 'other'),
    income: i.data['income'] == true,
    budget: _positive(i.data['budget']),
  );

  @override
  Map<String, dynamic> toData() => {'name': name, 'icon': icon, 'income': income, 'budget': budget};
}

class Person extends Model {
  const Person({required String id, required this.name, this.phone}) : super(id);
  final String name;
  final String? phone;

  @override
  String get type => 'person';

  static Person from(Item i) => Person(id: i.id, name: _str(i.data['name'], 'Someone'), phone: _opt(i.data['phone']));

  @override
  Map<String, dynamic> toData() => {'name': name, 'phone': phone};
}

class Entry extends Model {
  const Entry({
    required String id,
    required this.kind,
    required this.amount,
    required this.date,
    required this.account,
    this.category,
    this.to,
    this.person,
    this.note = '',
    this.photo = false,
    this.recurring,
  }) : super(id);

  final Kind kind;

  /// cents, always positive; [kind] says which way it went
  final int amount;
  final DateTime date;
  final String account;
  final String? category, person, recurring;

  /// the receiving account of a transfer
  final String? to;
  final String note;

  /// true when a receipt photo is stored on the device that added it
  final bool photo;

  @override
  String get type => 'entry';

  /// signed amount as seen in totals: money out is negative
  int get signed => kind == Kind.transfer ? 0 : amount * kind.sign;

  static Entry from(Item i) => Entry(
    id: i.id,
    kind: Kind.parse(i.data['kind']),
    amount: _int(i.data['amount']).abs(),
    date: _date(i.data['date']),
    account: _str(i.data['account']),
    category: _opt(i.data['category']),
    to: _opt(i.data['to']),
    person: _opt(i.data['person']),
    note: _str(i.data['note']),
    photo: i.data['photo'] == true,
    recurring: _opt(i.data['recurring']),
  );

  @override
  Map<String, dynamic> toData() => {
    'kind': kind.name,
    'amount': amount,
    'date': date.toIso8601String(),
    'account': account,
    'category': category,
    'to': to,
    'person': person,
    'note': note,
    'photo': photo,
    'recurring': recurring,
  };

  /// A new [id] makes a separate entry: the photo and the repeat stay with the original.
  Entry copyWith({
    String? id,
    Kind? kind,
    int? amount,
    DateTime? date,
    String? account,
    String? category,
    String? to,
    String? person,
    String? note,
    bool? photo,
  }) => Entry(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    account: account ?? this.account,
    category: category ?? this.category,
    to: to ?? this.to,
    person: person ?? this.person,
    note: note ?? this.note,
    photo: photo ?? (id == null && this.photo),
    recurring: id == null ? recurring : null,
  );
}

enum Every {
  day('Every day'),
  week('Every week'),
  month('Every month'),
  year('Every year');

  const Every(this.label);
  final String label;
}

/// A repeating entry, like rent or a salary. Occurrences are generated with
/// the id `<recurring id>-<yyyymmdd>` so two offline devices never double them.
class Recurring extends Model {
  const Recurring({
    required String id,
    required this.kind,
    required this.amount,
    required this.account,
    required this.start,
    this.every = Every.month,
    this.category,
    this.to,
    this.person,
    this.note = '',
    this.active = true,
  }) : super(id);

  final Kind kind;
  final int amount;
  final String account;
  final String? category, to, person;
  final String note;
  final Every every;

  /// first occurrence; its day of month is kept, clamped in short months
  final DateTime start;
  final bool active;

  @override
  String get type => 'recurring';

  static Recurring from(Item i) => Recurring(
    id: i.id,
    kind: Kind.parse(i.data['kind']),
    amount: _int(i.data['amount']).abs(),
    account: _str(i.data['account']),
    start: dayOf(_date(i.data['start'])),
    every: Every.values.asNameMap()[i.data['every']] ?? Every.month,
    category: _opt(i.data['category']),
    to: _opt(i.data['to']),
    person: _opt(i.data['person']),
    note: _str(i.data['note']),
    active: i.data['active'] != false,
  );

  @override
  Map<String, dynamic> toData() => {
    'kind': kind.name,
    'amount': amount,
    'account': account,
    'start': start.toIso8601String(),
    'every': every.name,
    'category': category,
    'to': to,
    'person': person,
    'note': note,
    'active': active,
  };

  DateTime occurrence(int n) => switch (every) {
    Every.day => DateTime(start.year, start.month, start.day + n),
    Every.week => DateTime(start.year, start.month, start.day + 7 * n),
    Every.month => _clamped(start.year, start.month + n, start.day),
    Every.year => _clamped(start.year + n, start.month, start.day),
  };

  static DateTime _clamped(int y, int m, int d) {
    final first = DateTime(y, m);
    return DateTime(first.year, first.month, d.clamp(1, daysInMonth(first.year, first.month)));
  }

  /// every occurrence on or before [until]
  Iterable<DateTime> dueUntil(DateTime until) sync* {
    for (var n = 0; ; n++) {
      final d = occurrence(n);
      if (d.isAfter(until)) return;
      yield d;
    }
  }

  DateTime nextAfter(DateTime day) {
    for (var n = 0; ; n++) {
      final d = occurrence(n);
      if (d.isAfter(day)) return d;
    }
  }

  String entryId(DateTime d) => '$id-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  Entry entryFor(DateTime d) => Entry(
    id: entryId(d),
    kind: kind,
    amount: amount,
    date: DateTime(d.year, d.month, d.day, 12),
    account: account,
    category: category,
    to: to,
    person: person,
    note: note,
    recurring: id,
  );
}
