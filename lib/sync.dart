import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'stats.dart';
import 'store.dart';

// Public by design: it only names the Firebase project. The server rules and
// the key's API restrictions are what protect the data.
const _apiKey = 'AIzaSyDes5BCZnBlJX6HhKWZCBmF-Xq5JVZWbGw';
// the firebase project id can't be renamed
const _docs = 'projects/kaudi-app/databases/(default)/documents';
const _page = 300;

enum Problem { offline, quota, signIn, update, failed }

class SyncError implements Exception {
  const SyncError(this.message, [this.problem = Problem.failed]);
  final String message;
  final Problem problem;

  @override
  String toString() => message;
}

/// A signed-in account. Only [key] can read the data; Firebase never sees it.
class Session {
  Session({required this.uid, required this.email, required this.refresh, required this.key, this.cursor});

  final String uid, email;
  String refresh;
  final List<int> key;

  /// server time up to which every change has been pulled
  String? cursor;

  String? idToken;
  DateTime expires = DateTime(0);

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'refresh': refresh,
    'key': base64Encode(key),
    'cursor': cursor,
  };

  static Session? load() {
    try {
      final j = jsonDecode(prefs.getString('sync') ?? '') as Map<String, dynamic>;
      return Session(
        uid: j['uid'] as String,
        email: j['email'] as String,
        refresh: j['refresh'] as String,
        key: base64Decode(j['key'] as String),
        cursor: j['cursor'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// End-to-end encrypted sync through Firestore's REST API.
///
/// Each record is one document: `v` holds the AES-GCM sealed record, `s` the
/// server write time. Pull asks for everything written after the cursor, push
/// sends every record edited here since the last push. Conflicts go to the
/// newest edit (see [Item.beats]).
class Sync extends ChangeNotifier {
  Sync(this.store) : _session = Session.load() {
    store.onEdit = () {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 3), syncNow);
    };
    _lifecycle = AppLifecycleListener(onResume: _wake);
    _timer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) syncNow();
    });
    _wake();
  }

  // repeats run after the pull when signed in, see _loop
  void _wake() => signedIn && !needsPassword ? syncNow() : store.runRecurring();

  final Store store;
  Session? _session;
  Timer? _debounce, _retry, _timer;
  AppLifecycleListener? _lifecycle;
  Future<void>? _running;
  bool _again = false, _closing = false;
  int _failures = 0;

  bool busy = false;
  DateTime? lastSync;

  /// what's stopping sync right now, in words for the user
  SyncError? problem;

  bool get signedIn => _session != null;
  String? get email => _session?.email;
  bool get needsPassword => problem?.problem == Problem.signIn;

  @override
  void dispose() {
    _debounce?.cancel();
    _retry?.cancel();
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  // ---- account ----

  /// Checks the password and returns a session that isn't saved yet, so the
  /// caller can ask what to do with this device's data before [start].
  Future<Session> signIn(String email, String password, {required bool create}) async {
    email = email.trim().toLowerCase();
    if (create && password.length < 10) {
      throw const SyncError('Use at least 10 characters. This password is the only lock on your synced data.');
    }
    final keys = await _derive(email, password);
    final res = await _post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:${create ? 'signUp' : 'signInWithPassword'}?key=$_apiKey',
      ),
      {'email': email, 'password': keys.auth, 'returnSecureToken': true},
    );
    return Session(uid: res['localId'] as String, email: email, refresh: res['refreshToken'] as String, key: keys.key)
      ..idToken = res['idToken'] as String
      ..expires = _expiry(res['expiresIn']);
  }

  /// Makes [s] the active account. With [keepLocal] this device's records are
  /// added to the account; otherwise the device is emptied and refilled from it.
  Future<void> start(Session s, {required bool keepLocal}) async {
    if (keepLocal) {
      await store.markAllDirty();
    } else {
      await store.wipe(keepSettings: store.onboarded);
    }
    _session = s;
    await _save();
    problem = null;
    notifyListeners();
    unawaited(syncNow());
    track('feature_used', {'name': keepLocal ? 'sync_on' : 'sync_join'});
  }

  /// After the server stopped accepting the saved sign-in.
  Future<void> reauth(String password) async {
    final old = _session!;
    final s = await signIn(old.email, password, create: false);
    if (s.uid != old.uid) throw const SyncError('That sign-in belongs to a different account.');
    s.cursor = old.cursor;
    _session = s;
    await _save();
    problem = null;
    notifyListeners();
    unawaited(syncNow());
  }

  Future<void> signOut({required bool removeData}) async {
    // stops a long first pull at the next page instead of waiting it out
    _closing = true;
    await _running;
    _closing = false;
    _session = null;
    problem = null;
    lastSync = null;
    await prefs.remove('sync');
    if (removeData) await store.wipe();
    notifyListeners();
  }

  /// Deletes every synced record and the account itself. Data on this device stays.
  Future<void> deleteAccount(String password) async {
    final s = await signIn(_session!.email, password, create: false);
    // no sync may push into the account while it's being emptied
    _closing = true;
    try {
      await _running;
      // keeps the cursor, so a delete that fails halfway doesn't cost a full download
      _session = s..cursor = _session!.cursor;
      while (true) {
        final rows = await _post(Uri.parse('https://firestore.googleapis.com/v1/$_docs/users/${s.uid}:runQuery'), {
          'structuredQuery': {
            'from': [
              {'collectionId': 'items'},
            ],
            'select': {
              'fields': [
                {'fieldPath': '__name__'},
              ],
            },
            'limit': 500,
          },
        }, auth: true) as List;
        final names = [
          for (final r in rows)
            if (r['document'] != null) r['document']['name'] as String,
        ];
        if (names.isEmpty) break;
        await _post(Uri.parse('https://firestore.googleapis.com/v1/$_docs:commit'), {
          'writes': [
            for (final n in names) {'delete': n},
          ],
        }, auth: true);
      }
      await _post(Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$_apiKey'), {
        'idToken': s.idToken,
      });
    } catch (_) {
      // a half-emptied account would hand the next device partial data, so upload it all again
      await store.markAllDirty();
      rethrow;
    } finally {
      _closing = false;
    }
    await signOut(removeData: false);
  }

  Future<void> _save() => prefs.setString('sync', jsonEncode(_session!.toJson()));

  // ---- the sync loop ----

  Future<void> syncNow() {
    if (_session == null || needsPassword || _closing) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    _retry?.cancel();
    busy = true;
    notifyListeners();
    do {
      _again = false;
      try {
        // repeats wait for the pull, so one deleted or changed on another device adds no stale entries
        await _pull().whenComplete(store.runRecurring);
        await _push();
        if (_closing) break;
        problem = null;
        lastSync = DateTime.now();
        _failures = 0;
      } catch (e) {
        final before = problem?.problem;
        problem = e is SyncError ? e : const SyncError('Sync hit a snag. It will try again soon.');
        // retries repeat the same problem every few minutes, so only a change counts
        if (problem!.problem != before) track('sync_problem', {'type': problem!.problem.name});
        if (e is! SyncError) debugPrint('sync: $e');
        if (problem!.problem != Problem.signIn && problem!.problem != Problem.update) {
          // 30 s, 1 min, 2 min ... capped at 30 min; a quota stop clears at midnight Pacific anyway
          _retry = Timer(Duration(seconds: min(30 << min(_failures++, 6), 1800)), syncNow);
        }
        break;
      }
    } while (_again && !_closing);
    busy = false;
    notifyListeners();
  }

  Future<void> _pull() async {
    final s = _session!;
    final since = s.cursor;
    String? readTime;
    List<Object>? after;
    while (true) {
      final rows = await _post(Uri.parse('https://firestore.googleapis.com/v1/$_docs/users/${s.uid}:runQuery'), {
        'structuredQuery': {
          'from': [
            {'collectionId': 'items'},
          ],
          if (since != null)
            'where': {
              'fieldFilter': {
                'field': {'fieldPath': 's'},
                'op': 'GREATER_THAN',
                'value': {'timestampValue': since},
              },
            },
          'orderBy': [
            {
              'field': {'fieldPath': 's'},
              'direction': 'ASCENDING',
            },
            {
              'field': {'fieldPath': '__name__'},
              'direction': 'ASCENDING',
            },
          ],
          // every write in one commit shares a timestamp, so page on (s, name), never s alone
          if (after != null) 'startAt': {'values': after, 'before': false},
          'limit': _page,
        },
      }, auth: true) as List;
      // sign out is waiting: return, not break, so a half-done pull saves no cursor
      if (_closing) return;
      readTime ??= rows.first['readTime'] as String;
      final docs = [
        for (final r in rows)
          if (r['document'] != null) r['document'] as Map<String, dynamic>,
      ];
      final items = <Item>[];
      for (final d in docs) {
        final item = await _open(d);
        if (item != null) items.add(item);
      }
      await store.merge(items);
      if (docs.length < _page) break;
      final last = docs.last;
      after = [
        {'timestampValue': last['fields']['s']['timestampValue']},
        {'referenceValue': last['name']},
      ];
    }
    // a commit can land up to a few seconds behind its own timestamp, so the
    // next pull re-reads the last two minutes instead of trusting readTime exactly
    final floor = DateTime.parse(readTime).subtract(const Duration(minutes: 2));
    if (since == null || floor.isAfter(DateTime.parse(since))) {
      s.cursor = floor.toUtc().toIso8601String();
      await _save();
    }
  }

  Future<void> _push() async {
    final s = _session!;
    final todo = store.dirty.toList();
    // ponytail: 200 writes per commit stays far under the 10 MiB request cap
    // because the store limits text fields; photos never sync.
    for (var i = 0; i < todo.length && !_closing; i += 200) {
      final batch = todo.sublist(i, min(i + 200, todo.length));
      await _post(Uri.parse('https://firestore.googleapis.com/v1/$_docs:commit'), {
        'writes': [
          for (final item in batch)
            {
              'update': {
                'name': '$_docs/users/${s.uid}/items/${item.id}',
                'fields': {
                  'v': {'bytesValue': await _seal(item)},
                },
              },
              'updateTransforms': [
                {'fieldPath': 's', 'setToServerValue': 'REQUEST_TIME'},
              ],
            },
        ],
      }, auth: true);
      await store.markPushed(batch);
    }
  }

  // ---- crypto ----

  static final _aes = AesGcm.with256bits();

  /// password -> PBKDF2 (600k rounds) -> two separate keys: one Firebase checks
  /// as the account password, one that encrypts and never leaves the device
  static Future<({String auth, List<int> key})> _derive(String email, String password) async {
    // windows and linux have no native pbkdf2, and the dart one takes ~16s, so keep it off the ui thread
    final pbkdf2 = FlutterCryptography.isPluginPresent || kIsWeb
        ? Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256)
        : BackgroundPbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256);
    final master = await pbkdf2.deriveKeyFromPassword(password: password, nonce: utf8.encode('spendrix:$email'));
    // android's native hmac rejects hkdf's empty salt, and this step is cheap anyway
    const hkdf = DartHkdf(hmac: DartHmac(DartSha256()), outputLength: 32);
    final auth = await hkdf.deriveKey(secretKey: master, info: utf8.encode('auth'));
    final key = await hkdf.deriveKey(secretKey: master, info: utf8.encode('enc'));
    return (auth: base64Url.encode(await auth.extractBytes()), key: await key.extractBytes());
  }

  List<int> _aad(String id) => utf8.encode('${_session!.uid}/$id');

  /// format byte 1, then 12-byte nonce, ciphertext, 16-byte tag
  Future<String> _seal(Item item) async {
    final json = item.toJson(withDirty: false)..remove('id');
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(json)),
      secretKey: SecretKey(_session!.key),
      aad: _aad(item.id),
    );
    return base64Encode(
      (BytesBuilder()
            ..addByte(1)
            ..add(box.nonce)
            ..add(box.cipherText)
            ..add(box.mac.bytes))
          .toBytes(),
    );
  }

  Future<Item?> _open(Map<String, dynamic> doc) async {
    final id = (doc['name'] as String).split('/').last;
    final Uint8List b;
    try {
      b = base64Decode(doc['fields']['v']['bytesValue'] as String);
    } catch (_) {
      return null;
    }
    if (b.isNotEmpty && b[0] > 1) {
      throw const SyncError(
        'Your account was synced by a newer Spendrix. Update the app to keep syncing.',
        Problem.update,
      );
    }
    if (b.length < 29 || b[0] != 1) return null;
    try {
      final clear = await _aes.decrypt(
        SecretBox(b.sublist(13, b.length - 16), nonce: b.sublist(1, 13), mac: Mac(b.sublist(b.length - 16))),
        secretKey: SecretKey(_session!.key),
        aad: _aad(id),
      );
      return Item.fromJson({...jsonDecode(utf8.decode(clear)) as Map<String, dynamic>, 'id': id});
    } catch (e) {
      // a damaged record is skipped; the next edit of it here overwrites it
      debugPrint('sync: skipped unreadable $id: $e');
      return null;
    }
  }

  // ---- http ----

  static DateTime _expiry(Object? seconds) =>
      DateTime.now().add(Duration(seconds: int.tryParse('$seconds') ?? 3600) - const Duration(minutes: 1));

  Future<String> _token() async {
    final s = _session!;
    if (s.idToken != null && DateTime.now().isBefore(s.expires)) return s.idToken!;
    // securetoken answers in snake_case, unlike the sign-in endpoints
    final res = await _post(Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'), {
      'grant_type': 'refresh_token',
      'refresh_token': s.refresh,
    });
    s
      ..idToken = res['id_token'] as String
      ..expires = _expiry(res['expires_in'])
      ..refresh = res['refresh_token'] as String;
    await _save();
    return s.idToken!;
  }

  Future<dynamic> _post(Uri url, Map<String, Object?> body, {bool auth = false}) async {
    for (var attempt = 0; ; attempt++) {
      final form = url.host == 'securetoken.googleapis.com';
      final http.Response res;
      try {
        res = await http
            .post(
              url,
              headers: {
                'Content-Type': form ? 'application/x-www-form-urlencoded' : 'application/json',
                if (auth) 'Authorization': 'Bearer ${await _token()}',
              },
              body: form ? body : jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));
      } on SyncError {
        rethrow;
      } on Exception {
        throw const SyncError("No internet right now. Everything is saved on this device.", Problem.offline);
      }
      if (res.statusCode == 401 && auth && attempt == 0) {
        _session!.idToken = null;
        continue;
      }
      final Object? json;
      try {
        json = res.body.isEmpty ? null : jsonDecode(res.body);
      } on FormatException {
        throw SyncError('Sync server answered oddly (${res.statusCode}). It will try again soon.');
      }
      if (res.statusCode < 300) return json;
      throw _error(res.statusCode, json);
    }
  }

  static SyncError _error(int status, Object? json) {
    final err = json is Map ? json['error'] : null;
    final code = err is Map ? '${err['message'] ?? err['status'] ?? ''}' : '$err';
    const messages = {
      'EMAIL_EXISTS': 'That email already has a Spendrix account. Sign in instead.',
      'INVALID_LOGIN_CREDENTIALS': 'Wrong email or password.',
      'INVALID_PASSWORD': 'Wrong email or password.',
      'EMAIL_NOT_FOUND': 'Wrong email or password.',
      'INVALID_EMAIL': "That email address doesn't look right.",
      'MISSING_EMAIL': 'Type your email address.',
    };
    for (final MapEntry(:key, :value) in messages.entries) {
      if (code.startsWith(key)) return SyncError(value);
    }
    if (code.startsWith('TOO_MANY_ATTEMPTS')) {
      return const SyncError('Too many tries. Wait a few minutes, then try again.');
    }
    if (const [
      'TOKEN_EXPIRED',
      'INVALID_REFRESH_TOKEN',
      'USER_DISABLED',
      'USER_NOT_FOUND',
      'INVALID_ID_TOKEN',
    ].any(code.startsWith)) {
      return const SyncError('Sign in again to keep syncing. Nothing on this device is lost.', Problem.signIn);
    }
    if (status == 429 || code == 'RESOURCE_EXHAUSTED') {
      return const SyncError(
        "Sync has hit today's free limit. It picks up again tomorrow, and nothing is lost.",
        Problem.quota,
      );
    }
    return SyncError('Sync failed ($status). It will try again soon.');
  }
}
