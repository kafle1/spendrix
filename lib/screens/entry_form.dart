import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../ai.dart';
import '../format.dart';
import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'people.dart';
import 'settings.dart';

/// Opens the add/edit screen.
/// - [entry] whose id is already in the store: edit it.
/// - [entry] with a fresh id: a prefilled draft (from AI or a shortcut); an empty or unknown account means "use the default".
/// - no [entry]: a new one of [kind], optionally for [person].
/// - [repeat] edits a saved Recurring's schedule and template fields instead.
/// [photo] attaches a picture; [guessed] marks the fields as AI guesses the user should check.
Future<void> openEntry(
  BuildContext context, {
  Entry? entry,
  Recurring? repeat,
  Kind? kind,
  String? person,
  Uint8List? photo,
  bool guessed = false,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    settings: const RouteSettings(name: 'entry'),
    fullscreenDialog: true,
    builder: (_) =>
        _EntryForm(entry: entry, repeat: repeat, kind: kind, person: person, photo: photo, guessed: guessed),
  ),
);

enum _Segment { expense, income, transfer, people }

_Segment _segmentOf(Kind k) => switch (k) {
  Kind.expense => _Segment.expense,
  Kind.income => _Segment.income,
  Kind.transfer => _Segment.transfer,
  Kind.gave || Kind.got => _Segment.people,
};

/// resizes to a 1600px long side and re-encodes as jpg, off the ui thread
Uint8List? _compressPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final long = decoded.width > decoded.height ? decoded.width : decoded.height;
  final resized = long <= 1600
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 1600 : null,
          height: decoded.height > decoded.width ? 1600 : null,
        );
  return img.encodeJpg(resized, quality: 80);
}

class _EntryForm extends StatefulWidget {
  const _EntryForm({this.entry, this.repeat, this.kind, this.person, this.photo, this.guessed = false});

  final Entry? entry;
  final Recurring? repeat;
  final Kind? kind;
  final String? person;
  final Uint8List? photo;
  final bool guessed;

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  late final bool isEdit;
  late Kind _kind;
  late String _account;
  String? _toAccount;
  String? _category;
  String? _person;
  late DateTime _date;

  /// what the keypad types; in [_fx] when that's set, else the home currency
  String _amount = '';

  /// the other currency it was paid in, and home cents per cent of it once known
  String? _fx;
  double? _rate;
  late final TextEditingController _noteController;
  Uint8List? _photoBytes;
  bool _photoChanged = false;
  Every? _repeat;
  int _every = 1;
  DateTime? _end;

  /// the date first shown for a repeat edit, so an untouched schedule keeps its old anchor
  late final DateTime? _repeatDateShown;
  late bool _guessed;
  bool _moreExpanded = false;
  bool _cameraSupported = false;
  bool _aiLoading = false;
  bool _saving = false;
  bool _dirty = false;
  String _personQuery = '';
  String? _error;
  final _formFocus = FocusNode(debugLabel: 'entry-form');

  @override
  void initState() {
    super.initState();
    final store = context.read<Store>();
    final e = widget.entry;
    final r = widget.repeat;
    isEdit = e != null && store.entry(e.id) != null;

    _kind = e?.kind ?? r?.kind ?? widget.kind ?? Kind.parse(prefs.getString('lastKind'));

    var account = e?.account ?? r?.account;
    // only a fresh draft gets defaulted; an edit (or a repeat edit) keeps a deleted account's id, same as category/person
    if (!isEdit && r == null && (account == null || account.isEmpty || store.account(account) == null)) {
      account = store.defaultAccount;
    }
    _account = account ?? '';
    _toAccount = e?.to ?? r?.to;
    _category = e?.category ?? r?.category;
    _person = e?.person ?? r?.person ?? widget.person;

    if (r != null) {
      _repeat = r.every;
      _every = r.n;
      _end = r.end;
      final today = dayOf(DateTime.now());
      // nextAfter is strict, so today - 1 lets a repeat due today still show today.
      // an ended one shows its last day and keeps its end, else saving it would backfill every missed month
      _date = r.nextAfter(DateTime(today.year, today.month, today.day - 1)) ?? r.dueUntil(today).lastOrNull ?? r.start;
      _repeatDateShown = _date;
      _amount = centsToInput(r.amount);
    } else {
      _date = e?.date ?? DateTime.now();
      if (e != null) _fillAmount(e, store);
      _repeatDateShown = null;
    }

    _noteController = TextEditingController(text: e?.note ?? r?.note ?? '')..addListener(_markDirty);
    _guessed = widget.guessed;
    _moreExpanded =
        _noteController.text.isNotEmpty || widget.photo != null || (e?.photo ?? false) || _fx != null || r != null;

    if (widget.photo != null) {
      _photoBytes = widget.photo;
    } else if (e != null && e.photo) {
      store.photo(e.id).then((bytes) {
        if (mounted && !_photoChanged) setState(() => _photoBytes = bytes);
      });
    }
    _cameraSupported = ImagePicker().supportsImageSource(ImageSource.camera);
  }

  @override
  void dispose() {
    _noteController.dispose();
    _formFocus.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// runs a field change, marks the form dirty and drops any stale validation error
  void _touch(VoidCallback fn) => setState(() {
    fn();
    _error = null;
    _dirty = true;
  });

  // a repeat can't carry a photo, so attaching one drops the repeat
  void _setPhoto(Uint8List? bytes) {
    _photoBytes = bytes;
    _photoChanged = true;
    if (bytes != null) _repeat = null;
  }

  // a draft paid in another currency may have no home amount yet (0), then the rate stays unknown
  void _fillAmount(Entry e, Store store) {
    final fx = e.fx;
    if (fx != null && fx.code != store.settings.currency) {
      _fx = fx.code;
      _amount = centsToInput(e.fxAmount!);
      _rate = e.amount > 0 ? e.amount / e.fxAmount! : null;
      _repeat = null;
    } else if (e.amount > 0) {
      _amount = centsToInput(e.amount);
    }
  }

  /// home cents for [typed] cents of [_fx], null until there's a rate
  int? _home(int typed) {
    final cents = _rate == null ? 0 : (typed * _rate!).round();
    return cents > 0 && cents < 100000000000000 ? cents : null;
  }

  Future<void> _pickFx(Store store) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: FractionallySizedBox(
          heightFactor: .85,
          child: CurrencyList(selected: _fx ?? store.settings.currency, onPick: (c) => Navigator.pop(context, c)),
        ),
      ),
    );
    if (code == null || !mounted) return;
    final fx = code == store.settings.currency ? null : code;
    if (fx == _fx) return;
    _touch(() {
      _fx = fx;
      _rate = fx == null ? null : store.rate(fx);
      if (fx != null) _repeat = null;
    });
  }

  Future<void> _typeHome(Store store, int typed) async {
    final cents = await showDialog<int>(
      context: context,
      builder: (_) => _HomeAmountDialog(
        home: store.currency,
        paid: money(typed, currencyOf(_fx!).besides(store.currency)),
        cents: _home(typed),
      ),
    );
    if (cents != null && mounted) _touch(() => _rate = cents / typed);
  }

  void _appendDigit(String d) {
    if (d == '.' && _amount.contains('.')) return;
    final next = _amount == '0' && d != '.' ? d : _amount + d;
    if (!RegExp(r'^\d{0,12}(\.\d{0,2})?$').hasMatch(next)) return;
    _touch(() => _amount = next);
  }

  void _backspace() {
    if (_amount.isEmpty) return;
    _touch(() => _amount = _amount.substring(0, _amount.length - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrlOrCmd = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    // a text box keeps its own keys, the keypad shortcuts are for everywhere else
    final typing = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if ((ctrlOrCmd && key == LogicalKeyboardKey.keyS) ||
        (!typing && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter))) {
      _save(context, context.read<Store>());
      return KeyEventResult.handled;
    }
    if (typing) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final char = event.character;
    if (char != null && RegExp(r'^[0-9.]$').hasMatch(char)) {
      _appendDigit(char);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 90);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final compressed = await compute(_compressPhoto, bytes);
      if (!mounted) return;
      if (compressed == null) {
        toast(context, "Couldn't read that photo.");
        return;
      }
      _touch(() => _setPhoto(compressed));
    } catch (_) {
      if (mounted) toast(context, "Couldn't read that photo.");
    }
  }

  Future<void> _scanReceipt(BuildContext context, Store store) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;
    setState(() {
      _aiLoading = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      final draft = await context.read<Assistant>().readReceipt(bytes);
      if (draft == null) {
        if (context.mounted) toast(context, "Couldn't read that receipt. Fill it in by hand.");
        return;
      }
      final compressed = await compute(_compressPhoto, bytes);
      if (!mounted) return;
      if (draft.note.isNotEmpty) _noteController.text = draft.note;
      _touch(() {
        _kind = draft.kind;
        _fillAmount(draft, store);
        if (store.account(draft.account) != null) _account = draft.account;
        if (draft.category != null) _category = draft.category;
        if (draft.to != null) _toAccount = draft.to;
        if (draft.person != null) _person = draft.person;
        _date = draft.date;
        if (compressed != null) _setPhoto(compressed);
        _guessed = true;
        _moreExpanded = _moreExpanded || _photoBytes != null || _noteController.text.isNotEmpty || _fx != null;
      });
    } on AiError catch (err) {
      if (context.mounted) toast(context, err.message);
    } catch (_) {
      if (context.mounted) toast(context, "Couldn't read that receipt. Fill it in by hand.");
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _delete(BuildContext context, Entry e) async {
    await removeWithUndo(context, [e], 'Deleted');
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _stopRepeating(BuildContext context, Store store, Recurring r) async {
    final ok = await confirm(
      context,
      title: 'Stop repeating?',
      body: 'Past entries stay. No new ones will be made.',
      action: 'Stop',
    );
    if (!ok || !context.mounted) return;
    await store.save(r.copyWith(active: false));
    if (context.mounted) toast(context, 'Stopped repeating');
  }

  Future<void> _rememberDefaults() async {
    await prefs.setString('lastKind', _kind.name);
    if (_account.isNotEmpty) await prefs.setString('lastAccount', _account);
  }

  Future<void> _save(BuildContext context, Store store) async {
    final typed = parseCents(_amount);
    if (typed == null) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    final cents = _fx == null ? typed : _home(typed);
    if (cents == null) {
      setState(() => _error = 'Add how much that is in ${store.currency.symbol}.');
      return;
    }
    if (_account.isEmpty) {
      setState(() => _error = 'Add an account first.');
      return;
    }
    // lent money with nobody on it would never show in what people owe
    if ((_kind == Kind.gave || _kind == Kind.got) && _person == null) {
      setState(() => _error = 'Choose a person.');
      return;
    }
    if (_kind == Kind.transfer) {
      if (_toAccount == null || _toAccount!.isEmpty) {
        setState(() => _error = 'Choose a "to" account.');
        return;
      }
      if (_toAccount == _account) {
        setState(() => _error = 'Pick two different accounts.');
        return;
      }
    }
    if (_saving) return;
    _saving = true;
    try {
      await _write(store, cents);
      await _rememberDefaults();
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) toast(context, "Couldn't save. Check free space and try again.");
    } finally {
      _saving = false;
    }
  }

  Future<void> _write(Store store, int cents) async {
    final category = _kind == Kind.expense || _kind == Kind.income ? _category : null;
    final to = _kind == Kind.transfer ? _toAccount : null;
    final person = _kind == Kind.gave || _kind == Kind.got ? _person : null;

    final editing = widget.repeat;
    if (editing != null) {
      // only re-anchor when the schedule actually moved, else past occurrence ids stay valid
      final sameSchedule = _repeat == editing.every && _every == editing.n && dayOf(_date) == _repeatDateShown;
      await store.save(
        Recurring(
          id: editing.id,
          kind: _kind,
          amount: cents,
          account: _account,
          start: sameSchedule ? editing.start : dayOf(_date),
          every: _repeat!,
          n: _every.clamp(1, 99),
          end: _end,
          category: category,
          to: to,
          person: person,
          note: _noteController.text.trim(),
          active: editing.active,
        ),
      );
      return;
    }

    if (!isEdit && _repeat != null) {
      await store.save(
        Recurring(
          id: newId(),
          kind: _kind,
          amount: cents,
          account: _account,
          start: dayOf(_date),
          every: _repeat!,
          n: _every.clamp(1, 99),
          end: _end,
          category: category,
          to: to,
          person: person,
          note: _noteController.text.trim(),
        ),
      );
      return;
    }

    // photos stay on the device that took them, so an edit elsewhere must keep the flag it can't see
    final keepPhoto = isEdit && !_photoChanged;
    final id = widget.entry?.id ?? newId();
    final fxAmount = _fx == null ? null : parseCents(_amount);
    await store.save(
      Entry(
        id: id,
        kind: _kind,
        amount: cents,
        date: _date,
        account: _account,
        category: category,
        to: to,
        person: person,
        note: _noteController.text.trim(),
        photo: keepPhoto ? widget.entry!.photo : _photoBytes != null,
        recurring: isEdit ? widget.entry!.recurring : null,
        fxCur: fxAmount == null ? null : _fx,
        fxAmount: fxAmount,
        fxHome: fxAmount == null ? null : cents,
      ),
    );
    if (!keepPhoto) await store.setPhoto(id, _photoBytes);
    if (!isEdit) track('entry_added', {'kind': _kind.name, 'via': _guessed ? 'ai' : 'manual'});
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final recurring = widget.entry?.recurring != null ? store.recurringOf(widget.entry!.recurring) : null;
    final canStopRepeating = isEdit && recurring != null && recurring.active;
    final assistantReady = context.watch<Assistant>().ready;
    // the soft keyboard eats vertical space too, so drop the numeric keypad while it's up
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final ok = await confirm(context, title: 'Discard changes?', action: 'Discard', destructive: true);
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.repeat != null ? 'Edit repeat' : (isEdit ? 'Edit' : 'New')),
          actions: [
            if (!isEdit && widget.repeat == null && !kIsWeb && assistantReady)
              _aiLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.document_scanner_outlined),
                      tooltip: 'Scan receipt',
                      onPressed: () => _scanReceipt(context, store),
                    ),
            if (canStopRepeating)
              IconButton(
                icon: const Icon(Icons.repeat),
                tooltip: 'Stop repeating',
                onPressed: () => _stopRepeating(context, store, recurring),
              ),
            if (isEdit)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _delete(context, widget.entry!),
              ),
          ],
        ),
        body: SafeArea(
          child: Focus(
            focusNode: _formFocus,
            autofocus: true,
            onKeyEvent: _onKey,
            child: Narrow(
              width: 560,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: [
                    if (_guessed) _guessedBanner(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _kindToggle(),
                            const SizedBox(height: 20),
                            _amountDisplay(store),
                            const SizedBox(height: 20),
                            if (_kind == Kind.expense || _kind == Kind.income) ...[
                              _sectionLabel('Category'),
                              _categoryGrid(store),
                              const SizedBox(height: 16),
                            ],
                            if (_kind == Kind.gave || _kind == Kind.got) ...[
                              _peopleToggle(),
                              const SizedBox(height: 12),
                              _sectionLabel('Person'),
                              _personPicker(store),
                              const SizedBox(height: 16),
                            ],
                            _sectionLabel(_kind == Kind.transfer ? 'From' : 'Account'),
                            _accountChips(store, selected: _account, onSelect: (id) => _touch(() => _account = id)),
                            if (_kind == Kind.transfer) ...[
                              const SizedBox(height: 12),
                              _sectionLabel('To'),
                              _accountChips(
                                store,
                                selected: _toAccount,
                                exclude: _account,
                                onSelect: (id) => _touch(() => _toAccount = id),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _sectionLabel('Date'),
                            _dateRow(),
                            const SizedBox(height: 8),
                            _moreSection(store),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    const SizedBox(height: 8),
                    if (!keyboardOpen) _keypad(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: () => _save(context, store), child: const Text('Save')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  Widget _guessedBanner() {
    final c = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: c.onTertiaryContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Filled in by AI. Check the amount and category before saving.',
              style: TextStyle(color: c.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kindToggle() {
    final selected = _segmentOf(_kind);
    // shrinks on narrow phones and big text sizes instead of scrolling half out of view
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SegmentedButton<_Segment>(
        segments: const [
          ButtonSegment(value: _Segment.expense, label: Text('Money out')),
          ButtonSegment(value: _Segment.income, label: Text('Money in')),
          ButtonSegment(value: _Segment.transfer, label: Text('Transfer')),
          ButtonSegment(value: _Segment.people, label: Text('People')),
        ],
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: (set) {
          final newSeg = set.first;
          _touch(() {
            if (newSeg != selected) _category = null;
            _kind = switch (newSeg) {
              _Segment.expense => Kind.expense,
              _Segment.income => Kind.income,
              _Segment.transfer => Kind.transfer,
              _Segment.people => _kind == Kind.gave || _kind == Kind.got ? _kind : Kind.gave,
            };
          });
        },
      ),
    );
  }

  Widget _amountDisplay(Store store) {
    final color = _kind == Kind.transfer ? null : moneyColor(context, _kind.sign);
    final big = Center(
      child: Text(
        typedMoney(_amount, _fx == null ? store.currency : currencyOf(_fx!).besides(store.currency)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.displaySmall
            ?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
    final typed = _fx == null ? null : parseCents(_amount);
    if (typed == null) return big;
    final home = _home(typed);
    return Column(
      children: [
        big,
        TextButton.icon(
          onPressed: () => _typeHome(store, typed),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: Text(home == null ? 'Add how much that is in ${store.currency.symbol}' : '= ${store.fmt(home)}'),
        ),
      ],
    );
  }

  Widget _keypad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', '⌫'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (final k in row) ...[Expanded(child: _keyButton(k)), if (k != row.last) const SizedBox(width: 8)],
              ],
            ),
          ),
      ],
    );
  }

  Widget _keyButton(String label) {
    final isBackspace = label == '⌫';
    return SizedBox(
      height: 64,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            isBackspace ? _backspace() : _appendDigit(label);
          },
          child: Center(
            child: isBackspace
                ? const Icon(Icons.backspace_outlined)
                : Text(label, style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
      ),
    );
  }

  Widget _categoryGrid(Store store) {
    final cats = store.categoriesFor(_kind);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final c in cats)
          _categoryTile(
            c.name,
            iconOf(c.icon),
            selected: _category == c.id,
            onTap: () => _touch(() => _category = c.id),
          ),
        _categoryTile(
          'New',
          Icons.add,
          selected: false,
          onTap: () async {
            final made = await editCategory(context, income: _kind == Kind.income);
            if (made != null && mounted) _touch(() => _category = made.id);
          },
        ),
      ],
    );
  }

  Widget _categoryTile(String name, IconData icon, {required bool selected, required VoidCallback onTap}) {
    final c = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: c.primary, width: 1.5) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBubble(icon),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _peopleToggle() => SegmentedButton<Kind>(
    segments: [
      ButtonSegment(value: Kind.gave, label: Text(Kind.gave.label)),
      ButtonSegment(value: Kind.got, label: Text(Kind.got.label)),
    ],
    selected: {_kind},
    showSelectedIcon: false,
    onSelectionChanged: (set) => _touch(() => _kind = set.first),
  );

  Widget _personPicker(Store store) {
    final people = store.people;
    final query = _personQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? people
        : [
            for (final p in people)
              if (p.name.toLowerCase().contains(query)) p,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (people.length > 8) ...[
          TextField(
            decoration: const InputDecoration(hintText: 'Search people', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _personQuery = v),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in filtered)
              ChoiceChip(
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                selected: _person == p.id,
                onSelected: (_) => _touch(() => _person = p.id),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('New person'),
              onPressed: () async {
                final made = await editPerson(context);
                if (made != null && mounted) _touch(() => _person = made.id);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _accountChips(
    Store store, {
    required String? selected,
    String? exclude,
    required ValueChanged<String> onSelect,
  }) {
    final list = [
      for (final a in store.accounts)
        if (a.id != exclude) a,
    ];
    final newChip = ActionChip(
      avatar: const Icon(Icons.add, size: 16),
      label: Text(list.isEmpty ? 'New account' : 'New'),
      onPressed: () async {
        final made = await editAccount(context);
        if (made != null && mounted) onSelect(made.id);
      },
    );
    if (list.isEmpty) return newChip;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in list)
          ChoiceChip(
            avatar: Icon(iconOf(a.icon), size: 16),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            selected: selected == a.id,
            onSelected: (_) => onSelect(a.id),
          ),
        newChip,
      ],
    );
  }

  // keeps the time of day, only the calendar day changes
  DateTime _keepTime(DateTime d) => DateTime(d.year, d.month, d.day, _date.hour, _date.minute);

  // moving a repeat's date can't clear an end that's now before it, so drop it back to "Never"
  void _setDate(DateTime d) => _touch(() {
    _date = d;
    if (_end != null && _end!.isBefore(dayOf(d))) _end = null;
  });

  Widget _dateRow() {
    final editingRepeat = widget.repeat != null;
    final today = dayOf(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final day = dayOf(_date);
    final isToday = day == today;
    final isYesterday = day == yesterday;
    // a far-out repeat's next date can sit past the usual year-ahead cap
    final farFuture = DateTime.now().add(const Duration(days: 365));
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(label: const Text('Today'), selected: isToday, onSelected: (_) => _setDate(_keepTime(today))),
        // a repeat can never be moved into the past, so hide the one shortcut that would do that
        if (!editingRepeat)
          ChoiceChip(
            label: const Text('Yesterday'),
            selected: isYesterday,
            onSelected: (_) => _setDate(_keepTime(yesterday)),
          ),
        ActionChip(
          label: Text(!isToday && !isYesterday ? dayLabel(_date) : 'Pick date'),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: editingRepeat ? today : DateTime(2000),
              lastDate: _date.isAfter(farFuture) ? _date : farFuture,
            );
            if (picked != null && mounted) _setDate(_keepTime(picked));
          },
        ),
      ],
    );
  }

  Widget _moreSection(Store store) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _moreExpanded = !_moreExpanded),
            icon: Icon(_moreExpanded ? Icons.expand_less : Icons.expand_more),
            label: Text(_moreExpanded ? 'Less' : 'More'),
          ),
        ),
        if (_moreExpanded) ...[
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Note'),
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          if (_repeat == null) ...[
            _sectionLabel('Photo'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_photoBytes != null) _photoPreview(),
                OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
                if (_cameraSupported)
                  OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
              ],
            ),
          ],
          if (_repeat == null) ...[
            const SizedBox(height: 16),
            _sectionLabel('Paid in'),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.currency_exchange, size: 16),
                label: Text(currencyOf(_fx ?? store.settings.currency).name),
                onPressed: () => _pickFx(store),
              ),
            ),
          ],
          if (!isEdit && _photoBytes == null && _fx == null) ...[
            const SizedBox(height: 16),
            _sectionLabel('Repeat'),
            _repeatSection(),
          ],
        ],
      ],
    );
  }

  Widget _repeatSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // pausing and deleting a saved repeat live in Settings, not here
          if (widget.repeat == null)
            ChoiceChip(
              label: const Text('None'),
              selected: _repeat == null,
              onSelected: (_) => _touch(() => _repeat = null),
            ),
          for (final ev in Every.values)
            ChoiceChip(label: Text(ev.label), selected: _repeat == ev, onSelected: (_) => _touch(() => _repeat = ev)),
        ],
      ),
      if (_repeat != null) ...[const SizedBox(height: 12), _intervalRow(), const SizedBox(height: 12), _endRow()],
    ],
  );

  Widget _intervalRow() {
    final unit = _every == 1 ? _repeat!.name : '${_repeat!.name}s';
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Every'),
        IconButton(
          tooltip: 'Fewer',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: _every > 1 ? () => _touch(() => _every--) : null,
        ),
        Text('$_every', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          tooltip: 'More',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _every < 99 ? () => _touch(() => _every++) : null,
        ),
        Text(unit),
      ],
    );
  }

  Widget _endRow() => Align(
    alignment: Alignment.centerLeft,
    child: _end == null
        ? ActionChip(label: const Text('Never'), onPressed: _pickEnd)
        : InputChip(
            label: Text('Ends ${dayLabel(_end!)}'),
            onPressed: _pickEnd,
            onDeleted: () => _touch(() => _end = null),
          ),
  );

  Future<void> _pickEnd() async {
    final start = dayOf(_date);
    final picked = await showDatePicker(
      context: context,
      // an old repeat can carry an end before its start, and the picker asserts on that
      initialDate: _end == null || _end!.isBefore(start) ? start : _end!,
      firstDate: start,
      lastDate: start.add(const Duration(days: 365 * 20)),
    );
    if (picked != null && mounted) _touch(() => _end = dayOf(picked));
  }

  Widget _photoPreview() {
    final bytes = _photoBytes!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'photo'),
                builder: (_) => _PhotoViewer(bytes),
              ),
            ),
            child: Image.memory(bytes, width: 88, height: 88, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: -8,
          top: -8,
          child: IconButton.filled(
            icon: const Icon(Icons.close, size: 16),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: () => _touch(() => _setPhoto(null)),
          ),
        ),
      ],
    );
  }
}

/// The exact home amount a foreign one came to, say from a bank app. Pops the cents.
class _HomeAmountDialog extends StatefulWidget {
  const _HomeAmountDialog({required this.home, required this.paid, this.cents});

  final Currency home;
  final String paid;
  final int? cents;

  @override
  State<_HomeAmountDialog> createState() => _HomeAmountDialogState();
}

class _HomeAmountDialogState extends State<_HomeAmountDialog> {
  late final _controller = TextEditingController(text: widget.cents == null ? '' : centsToInput(widget.cents!));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final cents = parseCents(_controller.text);
    if (cents == null) return setState(() => _error = 'Enter an amount.');
    Navigator.pop(context, cents);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('How much in ${widget.home.symbol}?'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _done(),
      decoration: InputDecoration(
        prefixText: '${widget.home.symbol} ',
        helperText: 'What ${widget.paid} came to. Your bank or card app shows it.',
        helperMaxLines: 2,
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _done, child: const Text('Done')),
    ],
  );
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer(this.bytes);
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: Center(child: InteractiveViewer(child: Image.memory(bytes))),
  );
}
