import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' show max;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'format.dart';
import 'models.dart';
import 'stats.dart';
import 'store.dart';
import 'widgets.dart' show icons;

enum AiStatus { unsupported, checking, missing, downloading, installed, loading, ready, failed }

/// One step of an answer. [text] is the whole answer so far, [draft] an entry to review, [act] a change to confirm.
class Reply {
  const Reply(this.text, {this.draft, this.act});
  final String text;
  final Entry? draft;
  final Act? act;
}

enum Task { repeat, remove, change, budget, create, stop }

/// A change the user asked for. Nothing happens until they tap it on the card.
class Act {
  const Act(this.task, this.title, this.detail, {this.save = const [], this.before = const [], this.drop});
  final Task task;
  final String title, detail;

  /// written on apply; [before] holds the copies they replace
  final List<Model> save, before;
  final Entry? drop;

  Future<void> apply(Store store) async {
    // save() also adds a new repeat's entries that are due
    for (final m in save) {
      await store.save(m);
    }
    if (drop != null) await store.remove([drop!.id]);
  }

  /// puts back what was there, and removes what was new along with a new repeat's entries
  Future<void> undo(Store store) async {
    final old = {for (final m in before) m.id};
    await store.remove([
      for (final m in save)
        if (!old.contains(m.id)) ...[
          m.id,
          for (final e in store.entries)
            if (e.recurring == m.id) e.id,
        ],
    ]);
    await store.saveAll([...before, ?drop]);
  }

  /// the same change, ready to apply again after an undo. A new repeat's dates stay deleted
  /// under its old id, so it needs a new one or they never come back.
  Act again() {
    final old = {for (final m in before) m.id};
    return Act(
      task,
      title,
      detail,
      save: [for (final m in save) m is Recurring && !old.contains(m.id) ? m.copyWith(id: newId()) : m],
      before: before,
      drop: drop,
    );
  }
}

typedef _Model = ({String repo, String rev, String file, int size});

/// On-device AI: Gemma 4 E2B, or E4B where there's memory to spare.
/// Nothing leaves the device except the one-time download.
/// Cheap to construct: the first read of [status] runs a quick "is it installed" check,
/// and the model itself loads on the first question.
class Assistant extends ChangeNotifier {
  Assistant(this.store);

  final Store store;

  // browsers only get text, where the small one is plenty
  static const _e2b = (
    repo: 'gemma-4-E2B-it-litert-lm',
    rev: 'b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1',
    file: kIsWeb ? 'gemma-4-E2B-it-web.litertlm' : 'gemma-4-E2B-it.litertlm',
    size: kIsWeb ? 2008432640 : 2588147712,
  );
  // reads Nepali and messy receipts better, at about twice the memory
  static const _e4b = (
    repo: 'gemma-4-E4B-it-litert-lm',
    rev: '2eee7ac325f20eb8c9ac1d0e972f7c84663062da',
    file: 'gemma-4-E4B-it.litertlm',
    size: 3659530240,
  );
  static const _pending = 'ai.downloading';
  static const _startError = kIsWeb
      ? "The AI couldn't start in this browser. It needs a recent Chrome or Edge."
      : "The AI couldn't start. Close other apps to free memory, then try again.";

  _Model _m = _e2b;
  // a fixed commit, so nobody can swap the model; the saved file keeps the same name
  String get _url => 'https://huggingface.co/litert-community/${_m.repo}/resolve/${_m.rev}/${_m.file}';

  /// download size, told to the user before they start
  int get sizeBytes => _m.size;

  // the engine only ships for these; Intel Macs, Windows on ARM and 32-bit Android can't run it
  static final bool supported =
      kIsWeb ||
      RegExp(r'"(android_arm64|ios_arm64|macos_arm64|windows_x64|linux_x64|linux_arm64)"').hasMatch(Platform.version);

  AiStatus _status = AiStatus.checking;
  double _progress = 0;
  String? _error;
  bool _busy = false, _stopped = false, _installed = false;
  CancelToken? _download;
  Timer? _idle;
  Future<void>? _boot, _started, _closing;
  Future<InferenceModel>? _model;
  InferenceModelSession? _session;

  AiStatus get status {
    if (!supported) return AiStatus.unsupported;
    // Future() so nothing notifies while a widget is still building
    _boot ??= Future(_check);
    return _status;
  }

  /// the model is downloaded and this device can run it
  bool get ready => const {AiStatus.installed, AiStatus.loading, AiStatus.ready}.contains(status);

  /// an answer or a receipt read is running
  bool get busy => _busy;

  /// 0 to 1 while downloading
  double get progress => _progress;

  /// what went wrong, in words for the user, while [status] is failed
  String? get error => _error;

  void _set(AiStatus s, [String? error]) {
    _status = s;
    _error = error;
    notifyListeners();
  }

  Future<void> _init() => _started ??= () async {
    try {
      await FlutterGemma.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
        webStorageMode: WebStorageMode.streaming,
      );
    } catch (_) {
      _started = null;
      rethrow;
    }
  }();

  Future<void> _check() async {
    _m = await _pick();
    try {
      await _init();
      // keep whichever one is already here, so an app update never downloads it again
      final have = [
        for (final m in [_e4b, _e2b])
          if (await FlutterGemma.isModelInstalled(m.file)) m,
      ];
      _installed = have.isNotEmpty;
      if (_installed) _m = have.first;
    } catch (_) {
      _set(AiStatus.failed, _startError);
      return;
    }
    if (_installed) {
      _set(AiStatus.installed);
    } else if (prefs.getBool(_pending) == true) {
      // the app was closed mid-download: pick it back up
      await download();
    } else {
      _set(AiStatus.missing);
    }
  }

  /// The model this device can run without slowing everything else down.
  static Future<_Model> _pick() async {
    if (kIsWeb) return _e2b;
    try {
      final info = DeviceInfoPlugin();
      // megabytes of memory, and what E4B needs: it takes about 3 GB on phones and Macs, 7 to 9 GB on a PC
      final (mb, need) = Platform.isAndroid
          ? ((await info.androidInfo).physicalRamSize, 10000)
          : Platform.isIOS
          ? ((await info.iosInfo).physicalRamSize, 10000)
          : Platform.isMacOS
          ? ((await info.macOsInfo).memorySize >> 20, 14000)
          : Platform.isWindows
          ? ((await info.windowsInfo).systemMemoryInMegabytes, 20000)
          : (_kb(await File('/proc/meminfo').readAsString()) >> 10, 20000);
      return mb >= need ? _e4b : _e2b;
    } catch (_) {
      return _e2b;
    }
  }

  static int _kb(String meminfo) => int.parse(RegExp(r'MemTotal:\s+(\d+)').firstMatch(meminfo)!.group(1)!);

  /// Downloads the model, about [sizeBytes]. Safe to call again after a failure.
  Future<void> download() async {
    if (_download != null) return;
    final token = _download = CancelToken();
    _progress = 0;
    _set(AiStatus.downloading);
    try {
      await prefs.setBool(_pending, true);
      await _init();
      await FlutterGemma.installModel(modelType: ModelType.gemma4, fileType: ModelFileType.litertlm)
          .fromNetwork(_url, foreground: true)
          .withProgress((p) {
            _progress = (p / 100).clamp(0.0, 1.0);
            notifyListeners();
          })
          .withCancelToken(token)
          .install();
      _installed = true;
      _set(AiStatus.installed);
      track('feature_used', {'name': 'ai_downloaded'});
    } catch (e) {
      if (token.isCancelled) {
        _set(AiStatus.missing);
      } else {
        track('feature_used', {'name': 'ai_download_failed'});
        _set(
          AiStatus.failed,
          e is DownloadException && e.error is NetworkError
              ? 'The download stopped. Check your internet and try again.'
              : 'The download failed. Try again in a bit.',
        );
      }
    } finally {
      _download = null;
      await prefs.remove(_pending);
    }
  }

  void cancelDownload() => _download?.cancel();

  /// after a failure: download again, or load the model again
  Future<void> retry() async {
    if (!_installed) return download();
    _set(AiStatus.installed);
    try {
      await _load();
      _rest();
    } on AiError {
      // _open already showed the reason
    }
  }

  /// Deletes the model file to free the space.
  Future<void> remove() async {
    _stopped = true;
    // wait for generation to actually stop before closing the model under it
    try {
      await _session?.stopGeneration();
    } catch (_) {}
    _download?.cancel();
    final model = _model;
    _model = null;
    await _close(model);
    try {
      await _init();
      await FlutterGemma.clearActiveInferenceIdentity();
      if (await FlutterGemma.isModelInstalled(_m.file)) await FlutterGemma.uninstallModel(_m.file);
      await prefs.remove(_pending);
      _installed = false;
      _m = await _pick();
      _set(AiStatus.missing);
    } catch (_) {
      _set(AiStatus.failed, "Couldn't remove the AI. Try again.");
    }
  }

  Future<InferenceModel> _load() {
    _idle?.cancel();
    return _model ??= _open();
  }

  Future<InferenceModel> _open() async {
    _set(AiStatus.loading);
    try {
      await _init();
      await _closing;
      // after a restart the active model can be unset; install() on a downloaded file only re-registers it
      if (!FlutterGemma.hasActiveModel()) {
        await FlutterGemma.installModel(
          modelType: ModelType.gemma4,
          fileType: ModelFileType.litertlm,
        ).fromNetwork(_url).install();
      }
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        supportImage: !kIsWeb,
        supportAudio: !kIsWeb,
        maxNumImages: kIsWeb ? null : 1,
      );
      _set(AiStatus.ready);
      return model;
    } catch (_) {
      _model = null;
      _set(AiStatus.failed, _startError);
      throw const AiError(_startError);
    }
  }

  void _claim() {
    if (!ready) throw AiError(_error ?? 'Download the AI in the Ask tab first.');
    if (_busy) throw const AiError('Wait for the current answer to finish.');
    _busy = true;
    _stopped = false;
    notifyListeners();
  }

  Future<void> _end() async {
    final session = _session;
    _session = null;
    try {
      await session?.close();
    } catch (_) {}
    _busy = false;
    _rest();
    notifyListeners();
  }

  // the loaded model holds 2 to 4 GB of memory, so give it back once the chat goes quiet
  void _rest() {
    _idle?.cancel();
    _idle = Timer(const Duration(minutes: 3), () {
      if (!_busy && _model != null) unawaited(_drop());
    });
  }

  // a failed call can leave the engine in a bad state, so the next one starts clean
  Future<void> _drop() async {
    final model = _model;
    _model = null;
    _status = AiStatus.installed;
    await _end();
    await _close(model);
  }

  // the plugin hands a closing model back to getActiveModel until close() returns, so loads wait on _closing
  Future<void> _close(Future<InferenceModel>? model) {
    final earlier = _closing;
    return _closing = () async {
      await earlier;
      try {
        await (await model)?.close();
      } catch (_) {}
    }();
  }

  /// stops the answer that is being written
  void stop() {
    _stopped = true;
    _session?.stopGeneration().catchError((_) {});
  }

  /// Answers from the user's own numbers, streaming the text as it grows.
  /// "Spent 250 on lunch" comes back as a draft entry, "delete the last one" as an [Act]. Nothing is saved.
  /// [earlier] is the last few chat messages, oldest first.
  Stream<Reply> ask(String question, {List<String> earlier = const []}) async* {
    // a Nepali transcript can carry Devanagari digits; normalise first so the digit guard and parsing see them
    question = _digits(question);
    // the small model reaches for an action even on questions, so a question only ever gets an answer
    final acts = !_asks(question);
    // no digit means any amount would be made up
    final digits = RegExp(r'\d').hasMatch(question);
    _claim();
    try {
      final model = await _load();
      final session = _session = await model.createSession(
        systemInstruction: _prompt(earlier, acts: acts),
        maxOutputTokens: 300,
      );
      // stop can be tapped while the model is still loading
      if (_stopped) return;
      await session.addQueryChunk(Message.text(text: question, isUser: true));
      var text = '';
      await for (final chunk in session.getResponseAsync()) {
        if (_stopped) break;
        text += chunk;
        // an entry comes back as json, keep it off screen until it's parsed
        if (!text.contains('{') && !text.contains('`')) yield Reply(text.replaceAll('**', '').trim());
      }
      final j = _json(text);
      // the small model fills find from the chat or the data list, so "delete the last entry" hit an old rent
      if (j != null && !_typed(_text(j['find']), question)) j['find'] = '';
      if (j != null) {
        yield acts ? _act(j, digits ? _cents(j['amount']) : null) : const Reply(_noAnswer);
      } else if (!_stopped) {
        final t = text.replaceAll('**', '').trim();
        yield Reply(t.isEmpty || t.contains('{') ? _noAnswer : t);
      }
    } on AiError {
      rethrow;
    } catch (_) {
      // stopping can end the stream with an error of its own
      if (_stopped) return;
      await _drop();
      throw const AiError('The AI hit a problem. Try again.');
    } finally {
      await _end();
    }
  }

  /// Reads a receipt or bill photo into a draft entry (fresh id, not saved), or
  /// null when nothing useful was found. Throws [AiError] with a message for the user.
  Future<Entry?> readReceipt(Uint8List image) async {
    if (kIsWeb) throw const AiError('Reading photos works in the phone and desktop apps.');
    _claim();
    try {
      final small = await compute(_shrink, image);
      if (small == null) throw const AiError("Couldn't open that photo. Try a JPG or PNG.");
      final model = await _load();
      final session = _session = await model.createSession(enableVisionModality: true, maxOutputTokens: 200);
      final names = [for (final c in store.categoriesFor(Kind.expense).take(30)) c.name];
      await session.addQueryChunk(
        Message.withImage(
          text:
              'Read this receipt or bill. Reply with only this JSON and nothing else: '
              '{"amount": 0, "currency": "", "merchant": "", "date": "YYYY-MM-DD", "category": ""}. '
              'amount is the final total paid, as a plain number. '
              'currency is its 3-letter code only if it is not ${store.settings.currency}, else "". '
              'merchant is the shop name. '
              'category is one of ${jsonEncode(names)}, or "" if none fit. '
              'Use "" for anything you can\'t read.',
          imageBytes: small,
          isUser: true,
        ),
      );
      final j = _json(await session.getResponse());
      final amount = _cents(j?['amount']);
      if (j == null || amount == null) return null;
      return _paidIn(
        Entry(
          id: newId(),
          kind: Kind.expense,
          amount: amount,
          date: _date(j['date']),
          account: '',
          category: _category(Kind.expense, j['category'])?.id,
          note: _clip(_text(j['merchant'])),
        ),
        j['currency'],
      );
    } on AiError {
      rethrow;
    } catch (_) {
      await _drop();
      throw const AiError("The AI couldn't read that photo. Try again.");
    } finally {
      await _end();
    }
  }

  /// Writes down what was said in a recorded clip, Nepali or English. Throws [AiError] for the user.
  Future<String> transcribe(Uint8List wav) async {
    if (kIsWeb) throw const AiError('Voice notes work in the phone and desktop apps.');
    _claim();
    try {
      final model = await _load();
      final session = _session = await model.createSession(
        enableAudioModality: true,
        maxOutputTokens: 120,
        temperature: 0.1,
      );
      await session.addQueryChunk(
        Message.withAudio(
          text:
              'Write down exactly what is said in this recording. It is Nepali or English. '
              'Keep Nepali in Devanagari. Write every number as digits 0-9. Output only the words, nothing else.',
          audioBytes: wav,
          isUser: true,
        ),
      );
      final text = (await session.getResponse()).trim();
      return text.replaceAll(RegExp(r'^[\s"‘’“”]+|[\s"‘’“”]+$'), '');
    } on AiError {
      rethrow;
    } catch (_) {
      await _drop();
      throw const AiError("Couldn't make out that recording. Try again.");
    } finally {
      await _end();
    }
  }

  /// The model's JSON as a draft or a change to confirm. [amount] is null when the message had no digit.
  Reply _act(Map<String, dynamic> j, int? amount) {
    String m(int cents) => store.fmt(cents);
    var find = _text(j['find']);
    // "the last one" is the default, not a search, but "last uber ride" still searches for "uber ride"
    find = find.replaceFirst(
      RegExp(r'^(the\s+)?((last|latest|recent|previous|that|this|it)\b\s*)?', caseSensitive: false),
      '',
    );
    if (RegExp(r'^(one|entry|expense|transaction)?$', caseSensitive: false).hasMatch(find)) find = '';
    final missing = find.isEmpty ? 'There are no entries yet.' : "I couldn't find an entry matching \"$find\".";

    switch (_text(j['do']).toLowerCase()) {
      case 'move':
        final from = _named(store.accounts, (a) => a.name, j['from']);
        final to = _named(store.accounts, (a) => a.name, j['to']);
        if (amount == null) return const Reply('Say how much to move, like "move 5000 from Cash to Bank".');
        if (from == null || to == null || from.id == to.id) {
          return Reply("I couldn't tell which accounts. You have ${store.accounts.map((a) => a.name).join(', ')}.");
        }
        return Reply(
          "Here's the transfer. Check it and save.",
          draft: Entry(
            id: newId(),
            kind: Kind.transfer,
            amount: amount,
            date: _date(j['date']),
            account: from.id,
            to: to.id,
            note: _clip(_text(j['note'])),
          ),
        );

      case 'delete':
        final e = _find(find);
        if (e == null) return Reply(missing);
        return Reply(
          'Delete this entry?',
          act: Act(Task.remove, _name(e), '${m(e.amount)} · ${dayLabel(e.date)}', drop: e),
        );

      case 'change':
        final e = _find(find);
        if (e == null) return Reply(missing);
        final hasCategory = e.kind == Kind.expense || e.kind == Kind.income;
        final category = hasCategory ? _named(store.categoriesFor(e.kind), (c) => c.name, j['category']) : null;
        final note = _clip(_text(j['note']));
        final after = e.copyWith(amount: amount, category: category?.id, note: note.isEmpty ? null : note);
        final changes = [
          if (after.amount != e.amount) '${m(e.amount)} → ${m(after.amount)}',
          if (after.category != e.category)
            '${store.category(e.category)?.name ?? 'Uncategorized'} → ${category!.name}',
          if (after.note != e.note) 'Note: ${after.note}',
        ];
        if (changes.isEmpty) return const Reply('Tell me what to change, like "make the last entry 300".');
        return Reply(
          'Change this entry?',
          act: Act(Task.change, _name(e), changes.join(' · '), save: [after], before: [e]),
        );

      case 'settle':
        final p = _named(store.people, (p) => p.name, j['person']);
        if (p == null) {
          return Reply("I couldn't find ${_text(j['person']).isEmpty ? 'that person' : j['person']} in People.");
        }
        final owed = store.owed(p.id);
        if (owed == 0) return Reply('You and ${p.name} are even.');
        final paid = amount ?? owed.abs();
        return Reply(
          owed > 0
              ? '${p.name} pays you ${m(paid)}. Check it and save.'
              : 'You pay ${p.name} ${m(paid)}. Check it and save.',
          draft: Entry(
            id: newId(),
            kind: owed > 0 ? Kind.got : Kind.gave,
            amount: paid,
            date: DateTime.now(),
            account: '',
            person: p.id,
          ),
        );

      case 'budget':
        if (amount == null && _cents(j['amount']) != null) {
          return const Reply('Say the amount, like "food budget 5000".');
        }
        final said = _text(j['category']);
        final String what;
        final int? now;
        final Model before, after;
        if (said.isEmpty) {
          final s = store.settings;
          (what, now, before, after) = ('Monthly budget', s.budget, s, Settings(currency: s.currency, budget: amount));
        } else {
          final c = _named(store.categoriesFor(Kind.expense), (c) => c.name, said);
          if (c == null) return Reply("I couldn't find a money out category called \"$said\".");
          (what, now, before, after) = (
            '${c.name} budget',
            c.budget,
            c,
            Category(id: c.id, name: c.name, icon: c.icon, income: c.income, budget: amount),
          );
        }
        if (amount == null && now == null) return const Reply('There is no budget set there to remove.');
        return Reply(
          amount == null ? 'Remove this budget?' : 'Set this budget?',
          act: Act(
            Task.budget,
            amount == null ? 'Remove the $what' : '$what: ${m(amount)} a month',
            now == null ? 'None set now' : 'Now ${m(now)}',
            save: [after],
            before: [before],
          ),
        );

      case 'new':
        final income = _text(j['kind']).toLowerCase() == 'income';
        bool taken(Iterable<String> names, String name) => names.any((n) => n.toLowerCase() == name.toLowerCase());
        final (person, account, category) = (
          _clip(_text(j['person']), 60),
          _clip(_text(j['account']), 60),
          _clip(_text(j['category']), 60),
        );
        final (String name, String kind, Model model, bool exists) = person.isNotEmpty
            ? (person, 'person', Person(id: newId(), name: person), taken(store.people.map((p) => p.name), person))
            : account.isNotEmpty
            ? (
                account,
                'account',
                Account(id: newId(), name: account, icon: _icon(account, 'wallet')),
                taken(store.allAccounts.map((a) => a.name), account),
              )
            : (
                category,
                income ? 'money in category' : 'money out category',
                Category(id: newId(), name: category, icon: _icon(category, 'other'), income: income),
                taken(store.categoriesFor(income ? Kind.income : Kind.expense).map((c) => c.name), category),
              );
        if (name.isEmpty) return const Reply('Tell me the name, like "add Hari to people".');
        if (exists) return Reply('You already have a $kind called $name.');
        return Reply('Add this?', act: Act(Task.create, name, 'New $kind', save: [model]));

      case 'stop':
        final s = find.toLowerCase();
        final live = [
          for (final r in store.recurring)
            if (r.active && _repeatName(r).toLowerCase().contains(s)) r,
        ];
        if (live.isEmpty) {
          return Reply(s.isEmpty ? 'Nothing is repeating right now.' : "I couldn't find a repeat matching \"$find\".");
        }
        if (s.isEmpty && live.length > 1) return Reply('Which one? ${live.map(_repeatName).join(', ')}.');
        final r = live.first;
        return Reply(
          'Stop this repeat?',
          act: Act(
            Task.stop,
            _repeatName(r),
            '${m(r.amount)} · ${r.label}',
            save: [r.copyWith(active: false)],
            before: [r],
          ),
        );
    }

    final e = _draft(j, amount);
    if (e == null) {
      return const Reply("I couldn't make an entry from that. Include the amount, like \"spent 250 on lunch\".");
    }
    final every = Every.values.asNameMap()[_text(j['every']).toLowerCase()];
    if (every == null) return Reply("Here's a draft. Check it and save.", draft: e);
    // a repeat is fixed up front: home currency only, and a person that's already saved
    if (e.fx != null) {
      return Reply("Repeats only work in ${store.settings.currency}, so here's a one-time draft.", draft: e);
    }
    final account = store.defaultAccount;
    if ((e.kind == Kind.gave || e.kind == Kind.got) && e.person == null || account == null) {
      return Reply("Here's the first one. Set it to repeat in Edit.", draft: e);
    }
    // a repeat may start later, like rent from next month; one-time entries can't be in the future
    final later = DateTime.tryParse(_text(j['date']));
    final start = later != null && later.isAfter(e.date) && later.year <= e.date.year + 1
        ? dayOf(later)
        : dayOf(e.date);
    final until = switch (DateTime.tryParse(_text(j['until']))) {
      final d? when !d.isBefore(start) => dayOf(d),
      _ => null,
    };
    final r = Recurring(
      id: newId(),
      kind: e.kind,
      amount: e.amount,
      account: account,
      start: start,
      every: every,
      n: j['n'] is num ? (j['n'] as num).toInt().clamp(1, 99) : 1,
      end: until,
      category: e.category,
      person: e.person,
      note: e.note,
    );
    return Reply(
      "Here's the repeat. Check it and save.",
      act: Act(
        Task.repeat,
        _repeatName(r),
        [
          '${m(r.amount)} · ${r.label}',
          'Starts ${dayLabel(start)}',
          if (until != null) 'Ends ${dayLabel(until)}',
        ].join(' · '),
        save: [r],
      ),
    );
  }

  /// whether the user typed a word of [find]; Devanagari can't be compared to the model's word, so it passes
  bool _typed(String find, String question) {
    final q = question.toLowerCase().replaceAll(',', '');
    if (find.isEmpty || q.codeUnits.any((c) => c >= 0x0900 && c <= 0x097F)) return true;
    const filler = {'the', 'and', 'one', 'last', 'entry'};
    return RegExp('[a-z0-9]+')
        .allMatches(find.toLowerCase().replaceAll(',', ''))
        .map((m) => m[0]!)
        .any((w) => (w.length > 2 || int.tryParse(w) != null) && !filler.contains(w) && q.contains(w));
  }

  /// the entry the user means: the last one they added or edited, or the newest that matches [find]
  Entry? _find(String find) {
    if (find.isEmpty) return store.lastTouched;
    final s = find.toLowerCase();
    final cents = parseCents(s);
    return store.entries.where((e) => _name(e).toLowerCase().contains(s) || e.amount == cents).firstOrNull;
  }

  /// "Food · lunch", "Ram", "Transfer"
  String _name(Entry e) => [
    store.person(e.person)?.name ?? store.category(e.category)?.name ?? e.kind.label,
    if (e.note.isNotEmpty) e.note,
  ].join(' · ');

  String _repeatName(Recurring r) => [
    store.person(r.person)?.name ?? store.category(r.category)?.name ?? r.kind.label,
    if (r.note.isNotEmpty) r.note,
  ].join(' · ');

  Entry? _draft(Map<String, dynamic> j, int? amount) {
    if (amount == null) return null;
    final kind =
        const {'income': Kind.income, 'gave': Kind.gave, 'got': Kind.got}[_text(j['kind']).toLowerCase()] ??
        Kind.expense;
    final withPerson = kind == Kind.gave || kind == Kind.got;
    final who = withPerson ? _text(j['person']) : '';
    final person = _named(store.people, (p) => p.name, who);
    // keep a name we don't know in the note so the user can pick or add the person
    final note = [if (who.isNotEmpty && person == null) who, _text(j['note'])].where((s) => s.isNotEmpty).join(' · ');
    return _paidIn(
      Entry(
        id: newId(),
        kind: kind,
        amount: amount,
        date: _date(j['date']),
        account: '',
        category: withPerson ? null : _category(kind, j['category'])?.id,
        person: person?.id,
        note: _clip(note),
      ),
      j['currency'],
    );
  }

  /// A draft said in another currency: converted at the last rate used, or 0 so the form asks.
  Entry _paidIn(Entry e, Object? code) {
    final c = currencies.where((c) => c.code == _text(code).toUpperCase()).firstOrNull;
    if (c == null || c.code == store.settings.currency) return e;
    final rate = store.rate(c.code);
    final home = rate == null ? 0 : (e.amount * rate).round();
    return e.copyWith(amount: home, fxCur: c.code, fxAmount: e.amount, fxHome: home);
  }

  Category? _category(Kind kind, Object? name) => _named(store.categoriesFor(kind), (c) => c.name, name);

  /// Facts worked out in code, so the model repeats numbers instead of inventing them.
  String _prompt(List<String> earlier, {required bool acts}) {
    final now = DateTime.now();
    final today = dayOf(now), tomorrow = DateTime(now.year, now.month, now.day + 1);
    final month = DateTime(now.year, now.month), next = DateTime(now.year, now.month + 1);
    final last = DateTime(now.year, now.month - 1);
    final cur = store.currency;
    String m(int cents) => store.fmt(cents);
    String name(String? category) => store.category(category)?.name ?? 'Uncategorized';
    String names(Kind kind) => store.categoriesFor(kind).take(30).map((c) => c.name).join(', ');

    final b = StringBuffer()
      ..writeln(
        'You are the money helper in Spendrix, a private money diary app. '
        'Today is ${DateFormat('EEEE, d MMMM y').format(now)}.',
      )
      ..writeln(
        'Answer in 1 to 3 short sentences of plain text, no markdown. Use only the facts below. '
        "Never guess or make up a number. If the facts don't cover it, say you don't know.",
      )
      ..writeln('Reply in the language the user wrote in, Nepali in Devanagari script or English.');
    if (acts) {
      b
        ..writeln(
          'If the user wants the app to do something, reply with only one of these JSON objects, in English, '
          'and nothing else. Never say you did it: the app shows it to them to confirm.',
        )
        ..writeln(
          'Money spent, received, given to or got from someone: {"do":"add","kind":"expense","amount":250,'
          '"currency":"","category":"Food","person":"","note":"lunch","date":"${DateFormat('yyyy-MM-dd').format(now)}"}',
        )
        ..writeln(
          'kind is expense, income, gave or got. amount is a plain number from their message. '
          'currency is a 3-letter code only when they name another currency, like 20 dollars (USD), else "". '
          'category is one of the category names below, matching Nepali words by meaning (khana is Food), or "". '
          'person is only for gave and got. date is today unless they say another day. '
          'If it repeats, like rent every month, add "every":"month" (day, week, month or year), '
          '"n":2 for every 2 months, and "until":"YYYY-MM-DD" only if they say when it ends.',
        )
        ..writeln(
          'Netflix 1200 every month: {"do":"add","kind":"expense","amount":1200,"currency":"","category":"",'
          '"person":"","note":"Netflix","every":"month"}',
        )
        ..writeln('Move money between accounts: {"do":"move","amount":5000,"from":"Cash","to":"Bank"}')
        ..writeln(
          'Delete an entry: {"do":"delete","find":""}. Change one: {"do":"change","find":"","amount":0,'
          '"category":"","note":""}, filling only what they want changed. find is a word from its note, '
          'category or person, or "" for the one they just added.',
        )
        ..writeln('Settle up with someone: {"do":"settle","person":"Ram"}')
        ..writeln('Monthly budget: {"do":"budget","amount":20000,"category":""}. Amount 0 removes it.')
        ..writeln(
          'Add a person, account or category by name, never for money with an amount: {"do":"new","person":"Hari"}, '
          '{"do":"new","account":"eSewa"}, {"do":"new","category":"Pets","kind":"expense"}',
        )
        ..writeln('Stop something that repeats: {"do":"stop","find":"Netflix"}');
    }
    b
      ..writeln()
      ..writeln('Facts:')
      ..writeln('Currency: ${cur.name} (${cur.code}, ${cur.symbol}).');
    if (store.entries.isEmpty) b.writeln('No entries yet.');
    b
      ..writeln('Money out today: ${m(store.spent(today, tomorrow))}.')
      ..writeln(
        'This month (${monthLabel(month)}) so far: money out ${m(store.spent(month, next))}, '
        'money in ${m(store.earned(month, next))}.',
      )
      ..writeln(
        'Last month (${monthLabel(last)}): money out ${m(store.spent(last, month))}, '
        'money in ${m(store.earned(last, month))}.',
      );

    final top = store.byCategory(month, next).take(5).map((e) => '${name(e.key)} ${m(e.value)}');
    if (top.isNotEmpty) b.writeln('Top money out this month: ${top.join(', ')}.');

    Entry? big;
    for (final e in store.entries) {
      if (e.kind == Kind.expense && !e.date.isBefore(month) && e.date.isBefore(next) && e.amount > (big?.amount ?? 0)) {
        big = e;
      }
    }
    if (big != null) {
      final note = big.note.isEmpty ? '' : ' (${_clip(big.note, 60)})';
      b.writeln(
        'Biggest single money out this month: ${m(big.amount)} on ${name(big.category)}$note, ${dayLabel(big.date)}.',
      );
    }

    final budget = store.settings.budget;
    String left(int limit, int used) => limit >= used ? '${m(limit - used)} left' : '${m(used - limit)} over';
    if (budget != null) b.writeln('Monthly budget: ${m(budget)}, ${left(budget, store.spent(month, next))}.');
    final limits = [
      for (final c in store.categoriesFor(Kind.expense))
        if (c.budget != null)
          '${c.name} ${m(c.budget!)} (${left(c.budget!, store.spent(month, next, category: c.id))})',
    ];
    if (limits.isNotEmpty) b.writeln('Category budgets this month: ${limits.take(6).join(', ')}.');

    final accounts = store.accounts;
    if (accounts.isNotEmpty) {
      b.writeln(
        'Accounts: ${accounts.take(8).map((a) => '${a.name} ${m(store.balance(a.id))}').join(', ')}. '
        'Total ${m(store.total)}.',
      );
    }

    final people = [
      for (final p in store.people)
        if (store.owed(p.id) != 0) p,
    ]..sort((x, y) => store.owed(y.id).abs().compareTo(store.owed(x.id).abs()));
    if (people.isNotEmpty) {
      final lines = people.take(8).map((p) {
        final owed = store.owed(p.id);
        return owed > 0 ? '${p.name} owes you ${m(owed)}' : 'you owe ${p.name} ${m(-owed)}';
      });
      b.writeln('People: ${lines.join(', ')}.');
    }

    b
      ..writeln('Money out categories: ${names(Kind.expense)}.')
      ..writeln('Money in categories: ${names(Kind.income)}.');
    if (earlier.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Recent messages, oldest first:')
        ..writeAll([for (final s in earlier) '- ${_clip(s, 300)}\n']);
    }
    return b.toString();
  }
}

const _noAnswer = "Sorry, I don't have an answer for that.";

String _text(Object? v) => v is String ? v.trim() : '';

// "can you delete it?" is a request, "how much did I spend?" a question
bool _asks(String q) {
  // "can you add rent?" is a request, but "could you tell me how much..." is still a question
  final polite = RegExp(r'^((please|pls|can you|could you|would you)\b\s*)+');
  final said = q.trim().toLowerCase(), s = said.replaceFirst(polite, '');
  return (s == said && s.endsWith('?')) ||
      RegExp(
        r'^(how|what|when|where|which|who|whose|why|is|are|am|was|were|do|does|did|have|has|show|tell|list|compare)\b',
      ).hasMatch(s) ||
      RegExp('(कति|कुन|कहाँ|कसले|कसलाई|किन|कहिले)').hasMatch(s);
}

/// the one named [said]: an exact match, or else the only one that contains it
T? _named<T>(Iterable<T> all, String Function(T) name, Object? said) {
  final s = _text(said).toLowerCase();
  if (s.isEmpty) return null;
  final near = all.where((x) => name(x).toLowerCase().contains(s)).toList();
  return near.where((x) => name(x).toLowerCase() == s).firstOrNull ?? (near.length == 1 ? near.first : null);
}

// a first guess from the name; the user can change it
String _icon(String name, String fallback) {
  const words = {
    'esewa': 'wallet',
    'khalti': 'wallet',
    'saving': 'savings',
    'credit': 'card',
    'rent': 'home',
    'petrol': 'fuel',
    'wifi': 'internet',
    'movie': 'fun',
    'doctor': 'health',
    'medicine': 'health',
    'school': 'education',
    'college': 'education',
    'gym': 'sports',
    'netflix': 'subscriptions',
  };
  final s = name.toLowerCase();
  for (final k in [...words.keys, ...icons.keys]) {
    if (RegExp('\\b$k').hasMatch(s)) return words[k] ?? k;
  }
  return fallback;
}

// Devanagari ०-९ to plain 0-9
String _digits(String s) =>
    String.fromCharCodes(s.codeUnits.map((c) => c >= 0x0966 && c <= 0x096F ? c - 0x0966 + 0x30 : c));

// by runes so an emoji is never cut in half
String _clip(String s, [int length = 100]) => String.fromCharCodes(s.trim().runes.take(length));

Map<String, dynamic>? _json(String text) {
  final start = text.indexOf('{');
  if (start < 0) return null;
  // the whole block first, then just the first object if the model kept talking
  for (final end in [text.lastIndexOf('}'), text.indexOf('}', start)]) {
    if (end <= start) continue;
    try {
      final v = jsonDecode(text.substring(start, end + 1));
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
  }
  return null;
}

int? _cents(Object? v) {
  if (v is num) return v.isFinite && v > 0 ? parseCents(v.toStringAsFixed(2)) : null;
  if (v is! String) return null;
  final m = RegExp(r'\d[\d.,]*').firstMatch(v);
  if (m == null) return null;
  // a minus before the digits, or an exponent right after, means it isn't a plain amount
  if (RegExp(r'-\s*$').hasMatch(v.substring(0, m.start)) || RegExp(r'^[eE]').hasMatch(v.substring(m.end))) return null;
  var s = m.group(0)!;
  // "1.234,50": a comma before the last two digits is the decimal point
  if (RegExp(r',\d{2}$').hasMatch(s)) s = s.replaceAll('.', '').replaceFirst(RegExp(r',(?=\d{2}$)'), '.');
  return parseCents(s.replaceAll(',', ''));
}

/// the day the model read, or now; never more than a day ahead
DateTime _date(Object? v) {
  final now = DateTime.now();
  final d = DateTime.tryParse(_text(v));
  if (d == null || d.year < 2000 || d.isAfter(now.add(const Duration(days: 1)))) return now;
  return dayOf(d) == dayOf(now) ? now : DateTime(d.year, d.month, d.day, 12);
}

/// Runs in an isolate: upright, at most 1024px on the long side, as jpg. Null when it isn't an image.
Uint8List? _shrink(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final image = img.bakeOrientation(decoded);
    final wide = image.width >= image.height;
    final fit = max(image.width, image.height) <= 1024
        ? image
        : img.copyResize(
            image,
            width: wide ? 1024 : null,
            height: wide ? null : 1024,
            interpolation: img.Interpolation.average,
          );
    return img.encodeJpg(fit, quality: 85);
  } catch (_) {
    return null;
  }
}

class AiError implements Exception {
  const AiError(this.message);
  final String message;

  @override
  String toString() => message;
}
