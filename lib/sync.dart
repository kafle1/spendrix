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

import 'google_auth.dart';
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
  Session({
    required this.uid,
    required this.email,
    required this.refresh,
    required this.key,
    this.cursor,
    this.google = false,
  });

  final String uid, email;
  String refresh;

  /// empty while a new device hasn't found or unlocked it yet
  List<int> key;

  /// server time up to which every change has been pulled
  String? cursor;

  /// false for a 2.1 password sign-in that hasn't moved over to Google yet
  final bool google;

  String? idToken;
  DateTime expires = DateTime(0);

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'refresh': refresh,
    'key': base64Encode(key),
    'cursor': cursor,
    'google': google,
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
        google: j['google'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A Google sign-in that hasn't changed anything on this device yet.
class Login {
  Login._(this.google, this.email);

  final GoogleTokens google;

  /// the account's email, which the old password was salted with
  final String email;

  /// null while Firebase wants the account's old password before it lets Google in
  Session? account;

  /// the account already holds synced entries
  bool hasData = true;

  /// the key came from Drive, so there's nothing to copy there
  bool inDrive = false;

  /// set when a device signs in again: the account it has to be
  String? expect;

  bool get unlocked => account?.key.isNotEmpty ?? false;
}

/// The key as people see it on "Show sync key": base64url in groups of four.
String showKey(List<int> key) =>
    base64Url.encode(key).replaceAll('=', '').replaceAllMapped(RegExp('.{4}(?!\$)'), (m) => '${m[0]} ');

List<int>? _readKey(String text) {
  try {
    final t = text.replaceAll(RegExp(r'[\s=]'), '').replaceAll('+', '-').replaceAll('/', '_');
    final k = base64Url.decode(base64Url.normalize(t));
    return k.length == 32 ? k : null;
  } on FormatException {
    return null;
  }
}

class _NoDrive implements Exception {}

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
  void _wake() => signedIn && !needsSignIn ? syncNow() : store.runRecurring();

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
  bool get needsSignIn => problem?.problem == Problem.signIn;

  /// still on a 2.1 password sign-in, see [moveToGoogle]
  bool get onPassword => _session?.google == false;

  /// for "Show sync key"
  List<int>? get key => _session?.key;

  @override
  void dispose() {
    _debounce?.cancel();
    _retry?.cancel();
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  // ---- account ----

  static const _elsewhere = SyncError(
    'That Google account syncs a different set of entries. Pick the one you use for Spendrix.',
  );
  static const _wrongPassword = SyncError("That password isn't right.");

  /// Signs in on a device that isn't syncing yet and looks for the key.
  /// Nothing on this device changes until [start].
  Future<Login> google(GoogleTokens g) => _guard(() async {
    final res = await _idp(g);
    final l = Login._(g, '${res['email'] ?? ''}'.trim().toLowerCase());
    if (res['needConfirmation'] == true) {
      if (l.email.isEmpty) throw const SyncError("Google sign-in didn't go through. Try again.");
      return l;
    }
    final a = l.account = _fresh(res, email: l.email, key: const []);
    final docs = await _sample(a);
    l.hasData = docs.isNotEmpty;
    var drive = g.drive;
    if (drive != null) {
      try {
        if (await _driveKey(a, drive, docs) case final k?) {
          a.key = k;
          l.inDrive = true;
          return l;
        }
      } on _NoDrive {
        drive = null;
      }
    }
    // only a brand new sync gets a new key; data already there needs the one that locked it
    if (l.hasData) return l;
    a.key = List.generate(32, (_) => Random.secure().nextInt(256));
    if (drive != null) {
      try {
        a.key = await _driveCreate(a, drive);
        l.inDrive = true;
      } on _NoDrive {
        // the key stays on this device, "Show sync key" can carry it over
      }
    }
    return l;
  });

  /// "Enter sync key" on a new device.
  Future<void> unlockWithKey(Login l, String text) => _guard(() async {
    final a = l.account!;
    final k = _readKey(text);
    if (k == null) throw const SyncError("That doesn't look like a sync key. Copy it again from a device that syncs.");
    if (!await _fits(a, k, await _sample(a))) throw const SyncError("That sync key doesn't open this account's entries.");
    a.key = k;
  });

  /// "Unlock with your old password", once, for data a 2.1 device synced.
  Future<void> unlockWithPassword(Login l, String password) => _guard(() async {
    if (l.account case final a?) {
      // the old key came from the password and the account's email, so the data itself says if it's right
      final keys = await _derive(await _accountEmail(a) ?? l.email, password);
      if (!await _fits(a, keys.key, await _sample(a))) throw _wrongPassword;
      a.key = keys.key;
      return;
    }
    // Firebase keeps this Google account out until the old password proves it's the same person
    final keys = await _derive(l.email, password);
    final res = await _post(Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_apiKey'), {
      'email': l.email,
      'password': keys.auth,
      'returnSecureToken': true,
    });
    if (l.expect != null && res['localId'] != l.expect) throw _elsewhere;
    final linked = await _idp(l.google, link: res['idToken'] as String);
    final a = _fresh(linked, email: l.email, key: keys.key);
    final docs = await _sample(a);
    l.hasData = docs.isNotEmpty;
    l.account = a;
  });

  /// Makes a finished [Login] the active account. Nothing on this device is
  /// removed: its own entries join the account, and with none of its own the
  /// account's settings win over the ones picked here.
  Future<void> start(Login l) async {
    final a = l.account!;
    if (!store.hasOwnData) await store.yieldSettings();
    await store.markAllDirty();
    _session = a;
    await _save();
    problem = null;
    notifyListeners();
    unawaited(syncNow());
    if (!l.inDrive) unawaited(_driveKeep(a, l.google.drive));
    track('feature_used', {'name': l.hasData ? 'sync_join' : 'sync_on'});
  }

  /// A 2.1 device that still syncs links Google to its account and copies its
  /// key to Drive. Same account, same key, so nothing uploads again.
  /// Returns false when the key didn't reach Drive.
  Future<bool> moveToGoogle(GoogleTokens g) => _guard(() async {
    final old = _session!;
    final res = await _idpFor(g, old);
    if (res['needConfirmation'] == true || res['localId'] != old.uid) {
      await _drop(res);
      throw _elsewhere;
    }
    final s = _resumed(old, res);
    final inDrive = await _driveKeep(s, g.drive);
    await _swap(s);
    return inDrive;
  });

  /// After the server stopped taking the saved sign-in. Returns a login that
  /// still needs the old password, or null when sync is back on.
  Future<Login?> reauth(GoogleTokens g) => _guard(() async {
    final old = _session!;
    final res = await _idpFor(g, old);
    if (res['needConfirmation'] != true) {
      if (res['localId'] == old.uid) {
        final s = _resumed(old, res);
        await _swap(s);
        unawaited(_driveKeep(s, g.drive));
        return null;
      }
      if (res['isNewUser'] != true) throw _elsewhere;
      // Firebase had never seen this Google account; drop the empty account it just made
      // and let the old password link it instead
      await _drop(res);
    }
    return Login._(g, old.email)..expect = old.uid;
  });

  /// Finishes [reauth] once the old password linked Google.
  Future<void> resume(Login l) async {
    final old = _session!;
    final a = l.account!;
    if (a.uid != old.uid) throw _elsewhere;
    final s = Session(uid: old.uid, email: old.email, refresh: a.refresh, key: old.key, cursor: old.cursor, google: true)
      ..idToken = a.idToken
      ..expires = a.expires;
    await _swap(s);
    unawaited(_driveKeep(s, l.google.drive));
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

  /// Deletes every synced record, the key in Drive and the account itself. Data on this device stays.
  Future<void> deleteAccount(GoogleTokens g) => _guard(() async {
    final old = _session!;
    final res = await _idpFor(g, old);
    if (res['needConfirmation'] == true || res['localId'] != old.uid) {
      await _drop(res);
      throw _elsewhere;
    }
    final s = _resumed(old, res);
    // no sync may push into the account while it's being emptied
    _closing = true;
    try {
      await _running;
      _session = s;
      while (true) {
        final rows = await _post(_query(s.uid), {
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
      if (g.drive case final drive?) {
        try {
          for (final id in await _driveList(s, drive)) {
            await _driveCall('DELETE', _driveUri('/drive/v3/files/$id'), drive);
          }
        } catch (e) {
          // with Drive unticked the key file can't be reached; it only opens data that's now gone
          debugPrint('drive: $e');
        }
      }
      await _post(Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$_apiKey'), {
        'idToken': await _token(),
      });
    } catch (_) {
      // a half-emptied account would hand the next device partial data, so upload it all again
      await store.markAllDirty();
      rethrow;
    } finally {
      _closing = false;
    }
    await signOut(removeData: false);
  });

  // swaps in a new sign-in for the same account, only once it's known to work
  Future<void> _swap(Session s) async {
    _session = s;
    await _save();
    problem = null;
    notifyListeners();
    unawaited(syncNow());
  }

  // turns odd failures and malformed answers into one plain line; nothing here has changed by then
  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on SyncError {
      rethrow;
    } catch (e) {
      debugPrint('sign-in: $e');
      throw const SyncError('Sign-in hit a snag. Nothing changed on this device. Try again.');
    }
  }

  Future<Map<String, dynamic>> _idp(GoogleTokens g, {String? link}) async {
    final res = await _post(Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$_apiKey'), {
      'requestUri': 'http://localhost',
      'postBody': Uri(
        queryParameters: {'id_token': g.idToken, 'providerId': 'google.com', 'nonce': ?g.nonce},
      ).query,
      'returnSecureToken': true,
      'idToken': ?link,
    }) as Map<String, dynamic>;
    if (res['errorMessage'] case final String code) throw _error(400, {'error': {'message': code}});
    return res;
  }

  // a fresh Google sign-in for the account this device already uses; a 2.1 account gets Google linked on the way
  Future<Map<String, dynamic>> _idpFor(GoogleTokens g, Session old) async {
    if (!old.google) {
      try {
        return await _idp(g, link: await _token());
      } on SyncError catch (e) {
        // already linked, or the saved sign-in ended: a plain sign-in says which account it is
        if (!identical(e, _elsewhere) && e.problem != Problem.signIn) rethrow;
      }
    }
    return _idp(g);
  }

  // a Google account Firebase had never seen makes an empty account; don't leave it lying around
  Future<void> _drop(Map<String, dynamic> res) async {
    if (res['isNewUser'] != true || res['idToken'] is! String) return;
    try {
      await _post(Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$_apiKey'), {
        'idToken': res['idToken'],
      });
    } catch (e) {
      debugPrint('sign-in: $e');
    }
  }

  static Session _fresh(Map<String, dynamic> res, {required String email, required List<int> key}) =>
      Session(uid: res['localId'] as String, email: email, refresh: res['refreshToken'] as String, key: key, google: true)
        ..idToken = res['idToken'] as String
        ..expires = _expiry(res['expiresIn']);

  static Session _resumed(Session old, Map<String, dynamic> res) =>
      _fresh(res, email: old.email, key: old.key)..cursor = old.cursor;

  Future<String?> _accountEmail(Session a) async {
    try {
      final res = await _post(Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$_apiKey'), {
        'idToken': await _token(a),
      });
      return ((res['users'] as List).first['email'] as String?)?.trim().toLowerCase();
    } catch (e) {
      debugPrint('sign-in: $e');
      return null;
    }
  }

  static Uri _query(String uid) => Uri.parse('https://firestore.googleapis.com/v1/$_docs/users/$uid:runQuery');

  /// a few synced records, to check a key against
  Future<List<Map<String, dynamic>>> _sample(Session a) async {
    final rows = await _post(_query(a.uid), {
      'structuredQuery': {
        'from': [
          {'collectionId': 'items'},
        ],
        'limit': 5,
      },
    }, auth: true, as: a) as List;
    return [
      for (final r in rows)
        if (r['document'] != null) r['document'] as Map<String, dynamic>,
    ];
  }

  Future<bool> _fits(Session a, List<int> key, List<Map<String, dynamic>> docs) async {
    if (docs.isEmpty) return true;
    final test = Session(uid: a.uid, email: a.email, refresh: '', key: key);
    for (final d in docs) {
      if (await _open(d, test) != null) return true;
    }
    return false;
  }

  // ---- the key in Google Drive's app folder ----

  static Uri _driveUri(String path, [Map<String, String>? query]) => Uri.https('www.googleapis.com', path, query);

  /// 401 and 403 mean no Drive (unticked, expired or blocked); a rate limit is worth a retry
  static Future<http.Response> _driveCall(String method, Uri url, String token, {String? body, String? type}) async {
    final http.Response res;
    try {
      final req = http.Request(method, url)..headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        req
          ..headers['Content-Type'] = type!
          ..body = body;
      }
      res = await req.send().then(http.Response.fromStream).timeout(const Duration(seconds: 30));
    } on Exception {
      throw const SyncError('No internet right now. Everything is saved on this device.', Problem.offline);
    }
    if (res.statusCode < 300 || res.statusCode == 404) return res;
    if (res.statusCode == 429 || res.body.contains('ateLimitExceeded')) {
      throw const SyncError('Google Drive is busy right now. Try again in a minute.');
    }
    if (res.statusCode == 401 || res.statusCode == 403) throw _NoDrive();
    throw SyncError("Google Drive didn't answer (${res.statusCode}). Try again.");
  }

  /// key files for [a], oldest first
  static Future<List<String>> _driveList(Session a, String token) async {
    final res = await _driveCall(
      'GET',
      _driveUri('/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name = 'key-${a.uid}'",
        'fields': 'files(id,createdTime)',
        'pageSize': '100',
      }),
      token,
    );
    if (res.statusCode == 404) throw _NoDrive();
    final files = ((jsonDecode(res.body) as Map)['files'] as List).cast<Map<String, dynamic>>()
      ..sort((x, y) {
        final c = '${x['createdTime']}'.compareTo('${y['createdTime']}');
        return c != 0 ? c : '${x['id']}'.compareTo('${y['id']}');
      });
    return [for (final f in files) f['id'] as String];
  }

  /// the oldest key in Drive that opens [docs], null when there's none
  Future<List<int>?> _driveKey(Session a, String token, List<Map<String, dynamic>> docs) async {
    for (final id in await _driveList(a, token)) {
      final res = await _driveCall('GET', _driveUri('/drive/v3/files/$id', {'alt': 'media'}), token);
      final k = res.statusCode == 404 ? null : _readKey(res.body);
      if (k != null && await _fits(a, k, docs)) return k;
    }
    return null;
  }

  static Future<String> _driveUpload(Session a, String token, List<int> key) async {
    const b = 'spendrix-key';
    final meta = jsonEncode({
      'name': 'key-${a.uid}',
      'parents': ['appDataFolder'],
    });
    final res = await _driveCall(
      'POST',
      _driveUri('/upload/drive/v3/files', {'uploadType': 'multipart', 'fields': 'id'}),
      token,
      type: 'multipart/related; boundary=$b',
      body:
          '--$b\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
          '--$b\r\nContent-Type: text/plain\r\n\r\n${base64Url.encode(key)}\r\n--$b--',
    );
    if (res.statusCode == 404) throw _NoDrive();
    return (jsonDecode(res.body) as Map)['id'] as String;
  }

  /// Uploads a brand new key. Two devices can race to make one; both end up on the oldest.
  Future<List<int>> _driveCreate(Session a, String token) async {
    final mine = await _driveUpload(a, token, a.key);
    final first = await _driveKey(a, token, const []);
    if (first == null || listEquals(first, a.key)) return a.key;
    try {
      await _driveCall('DELETE', _driveUri('/drive/v3/files/$mine'), token);
    } catch (e) {
      debugPrint('drive: $e');
    }
    return first;
  }

  /// Puts [a]'s key in Drive unless it's already there. Never throws; false when it didn't get there.
  Future<bool> _driveKeep(Session a, String? token) async {
    if (token == null) return false;
    try {
      for (final id in await _driveList(a, token)) {
        final res = await _driveCall('GET', _driveUri('/drive/v3/files/$id', {'alt': 'media'}), token);
        if (res.statusCode != 404 && listEquals(_readKey(res.body), a.key)) return true;
      }
      await _driveUpload(a, token, a.key);
      return true;
    } catch (e) {
      debugPrint('drive: $e');
      return false;
    }
  }

  Future<void> _save() => prefs.setString('sync', jsonEncode(_session!.toJson()));

  // ---- the sync loop ----

  Future<void> syncNow() {
    if (_session == null || needsSignIn || _closing) return Future.value();
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
      final rows = await _post(_query(s.uid), {
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

  static List<int> _aad(Session s, String id) => utf8.encode('${s.uid}/$id');

  /// format byte 1, then 12-byte nonce, ciphertext, 16-byte tag
  Future<String> _seal(Item item) async {
    final s = _session!;
    final json = item.toJson(withDirty: false)..remove('id');
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(json)),
      secretKey: SecretKey(s.key),
      aad: _aad(s, item.id),
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

  Future<Item?> _open(Map<String, dynamic> doc, [Session? s]) async {
    s ??= _session!;
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
        secretKey: SecretKey(s.key),
        aad: _aad(s, id),
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

  Future<String> _token([Session? s]) async {
    s ??= _session!;
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
    if (identical(s, _session)) await _save();
    return s.idToken!;
  }

  /// [as] signs the call as an account that isn't active yet
  Future<dynamic> _post(Uri url, Map<String, Object?> body, {bool auth = false, Session? as}) async {
    for (var attempt = 0; ; attempt++) {
      final form = url.host == 'securetoken.googleapis.com';
      final http.Response res;
      try {
        res = await http
            .post(
              url,
              headers: {
                'Content-Type': form ? 'application/x-www-form-urlencoded' : 'application/json',
                if (auth) 'Authorization': 'Bearer ${await _token(as)}',
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
        (as ?? _session!).idToken = null;
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
    if (code.startsWith('FEDERATED_USER_ID_ALREADY_LINKED') || code.startsWith('PROVIDER_ALREADY_LINKED')) {
      return _elsewhere;
    }
    if (const ['INVALID_LOGIN_CREDENTIALS', 'INVALID_PASSWORD', 'EMAIL_NOT_FOUND'].any(code.startsWith)) {
      return _wrongPassword;
    }
    const messages = {
      'EMAIL_EXISTS': "That Google account's email already has its own Spendrix account. Pick another Google account.",
      'INVALID_IDP_RESPONSE': "Google sign-in didn't go through. Try again.",
      'MISSING_OR_INVALID_NONCE': "Google sign-in didn't go through. Try again.",
      'OPERATION_NOT_ALLOWED': "Google sign-in isn't set up in this build yet.",
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
      'CREDENTIAL_TOO_OLD_LOGIN_AGAIN',
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
