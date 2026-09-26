import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show max;

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'format.dart';
import 'models.dart';
import 'stats.dart';
import 'store.dart';

enum AiStatus { unsupported, checking, missing, downloading, installed, loading, ready, failed }

/// One step of an answer. [text] is the whole answer so far, [draft] an entry to review.
class Reply {
  const Reply(this.text, [this.draft]);
  final String text;
  final Entry? draft;
}

/// On-device AI (Gemma 4 E2B). Nothing leaves the device except the one-time download.
/// Cheap to construct: the first read of [status] runs a quick "is it installed" check,
/// and the model itself loads on the first question.
class Assistant extends ChangeNotifier {
  Assistant(this.store);

  final Store store;

  static const _file = kIsWeb ? 'gemma-4-E2B-it-web.litertlm' : 'gemma-4-E2B-it.litertlm';
  static const _url = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/$_file';
  static const _pending = 'ai.downloading';
  static const _startError = kIsWeb
      ? "The AI couldn't start in this browser. It needs a recent Chrome or Edge."
      : "The AI couldn't start. Close other apps to free memory, then try again.";

  /// download size, told to the user before they start
  static const sizeBytes = kIsWeb ? 2008432640 : 2588147712;

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
    try {
      await _init();
      _installed = await FlutterGemma.isModelInstalled(_file);
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
      if (await FlutterGemma.isModelInstalled(_file)) await FlutterGemma.uninstallModel(_file);
      await prefs.remove(_pending);
      _installed = false;
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

  // the loaded model holds about 2 GB of memory, so give it back once the chat goes quiet
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
  /// "Spent 250 on lunch" comes back as a draft entry instead. Nothing is saved.
  /// [earlier] is the last few chat messages, oldest first.
  Stream<Reply> ask(String question, {List<String> earlier = const []}) async* {
    // a Nepali transcript can carry Devanagari digits; normalise first so the digit guard and parsing see them
    question = _digits(question);
    // no digit means any amount would be made up, and the small model grabs the entry route for questions too
    final entry = RegExp(r'\d').hasMatch(question);
    _claim();
    try {
      final model = await _load();
      final session = _session = await model.createSession(
        systemInstruction: _prompt(earlier, entry: entry),
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
      if (j != null) {
        final draft = entry ? _draft(j) : null;
        yield draft == null
            ? const Reply("I couldn't make an entry from that. Include the amount, like \"spent 250 on lunch\".")
            : Reply("Here's a draft. Check it and save.", draft);
      } else if (!_stopped) {
        final t = text.replaceAll('**', '').trim();
        yield Reply(t.isEmpty || t.contains('{') ? "Sorry, I don't have an answer for that." : t);
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
              '{"amount": 0, "merchant": "", "date": "YYYY-MM-DD", "category": ""}. '
              'amount is the final total paid, as a plain number. merchant is the shop name. '
              'category is one of ${jsonEncode(names)}, or "" if none fit. '
              'Use "" for anything you can\'t read.',
          imageBytes: small,
          isUser: true,
        ),
      );
      final j = _json(await session.getResponse());
      final amount = _cents(j?['amount']);
      if (j == null || amount == null) return null;
      return Entry(
        id: newId(),
        kind: Kind.expense,
        amount: amount,
        date: _date(j['date']),
        account: '',
        category: _category(Kind.expense, j['category'])?.id,
        note: _clip(_text(j['merchant'])),
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

  Entry? _draft(Map<String, dynamic> j) {
    final amount = _cents(j['amount']);
    if (amount == null) return null;
    final kind =
        const {'income': Kind.income, 'gave': Kind.gave, 'got': Kind.got}[_text(j['kind']).toLowerCase()] ??
        Kind.expense;
    final withPerson = kind == Kind.gave || kind == Kind.got;
    final who = withPerson ? _text(j['person']) : '';
    final person = who.isEmpty
        ? null
        : store.people.where((p) => p.name.toLowerCase() == who.toLowerCase()).firstOrNull;
    // keep a name we don't know in the note so the user can pick or add the person
    final note = [if (who.isNotEmpty && person == null) who, _text(j['note'])].where((s) => s.isNotEmpty).join(' · ');
    return Entry(
      id: newId(),
      kind: kind,
      amount: amount,
      date: _date(j['date']),
      account: '',
      category: withPerson ? null : _category(kind, j['category'])?.id,
      person: person?.id,
      note: _clip(note),
    );
  }

  Category? _category(Kind kind, Object? name) {
    final n = _text(name).toLowerCase();
    return n.isEmpty ? null : store.categoriesFor(kind).where((c) => c.name.toLowerCase() == n).firstOrNull;
  }

  /// Facts worked out in code, so the model repeats numbers instead of inventing them.
  String _prompt(List<String> earlier, {required bool entry}) {
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
    if (entry) {
      b
        ..writeln(
          'If the user tells you about money they spent, received, gave to someone or got from someone, '
          'and is not asking a question, reply with only this JSON in English and nothing else:',
        )
        ..writeln(
          '{"kind":"expense","amount":250,"category":"Food","person":"","note":"lunch",'
          '"date":"${DateFormat('yyyy-MM-dd').format(now)}"}',
        )
        ..writeln(
          'kind is expense, income, gave or got. amount is a plain number from their message. '
          'category is one of the category names below, matching Nepali words by meaning (khana is Food), or "". '
          'person is only for gave and got. '
          'date is today unless they say another day.',
        );
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

String _text(Object? v) => v is String ? v.trim() : '';

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
