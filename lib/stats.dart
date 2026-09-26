import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'store.dart';

// Google Analytics 4, sent with the Measurement Protocol. Empty turns stats off and hides the question.
const _measurementId = '';
const _apiSecret = '';

/// Anonymous usage counts, sent only after the user says yes. Only fixed names and
/// rough counts leave the device: never amounts, names, notes, photos, audio or typed text.
const statsAvailable = _measurementId != '';

/// null until the user answers the question on Home
final statsOn = ValueNotifier<bool?>(statsAvailable ? prefs.getBool('stats') : false);

final _queue = <String>[];
final _active = Stopwatch();
final _errors = <String>{};
var _session = 0, _generation = 0;
DateTime? _hiddenAt;
Timer? _timer;
Future<void>? _sending;
Map<String, Object>? _common;
late Map<String, Object> Function() _snapshot;

/// Hooks errors and the app lifecycle. [snapshot] gives the once-a-day overview.
void startStats(Map<String, Object> Function() snapshot) {
  if (!statsAvailable) return;
  _snapshot = snapshot;
  _queue.addAll(prefs.getStringList('stats.queue') ?? const []);
  final flutterError = FlutterError.onError;
  FlutterError.onError = (d) {
    trackError(d.exception, d.stack);
    flutterError?.call(d);
  };
  final platformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (e, s) {
    trackError(e, s, fatal: true);
    return platformError?.call(e, s) ?? false;
  };
  AppLifecycleListener(
    onHide: () {
      _hiddenAt = DateTime.now();
      track('app_leave');
      _active.stop();
      unawaited(_flush());
    },
    onShow: () {
      _active.start();
      // GA starts a new session after 30 minutes away too
      if (DateTime.now().difference(_hiddenAt ?? DateTime.now()) > const Duration(minutes: 30)) _open();
    },
  );
  _active.start();
  _open();
}

/// Counts a page as opened, by a fixed name, never anything shown on it.
void trackScreen(String name) => track('page_view', {'page_title': name});

/// Counts pages pushed with a [RouteSettings] name.
final statsObserver = _Observer();

class _Observer extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name case final name?) trackScreen(name);
  }
}

void _open() {
  _session = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  track('app_open');
  final day = DateTime.now().toIso8601String().substring(0, 10);
  if (statsOn.value == true && prefs.getString('stats.day') != day) {
    track('snapshot', _snapshot());
    unawaited(prefs.setString('stats.day', day));
  }
}

Future<void> setStats(bool on) async {
  await prefs.setBool('stats', on);
  statsOn.value = on;
  if (on) {
    _open();
  } else {
    await resetStats();
  }
}

/// Forgets this device's stats id and anything not yet sent.
Future<void> resetStats() async {
  _generation++;
  _queue.clear();
  _common = null;
  await prefs.remove('stats.id');
  await prefs.remove('stats.queue');
  await prefs.remove('stats.day');
}

/// Queues one event. [params] must only hold fixed names and bucketed counts.
void track(String name, [Map<String, Object> params = const {}]) {
  if (statsOn.value != true) return;
  final ms = max(1, _active.elapsedMilliseconds);
  _active.reset();
  _queue.add(
    jsonEncode({
      'name': name,
      'timestamp_micros': DateTime.now().microsecondsSinceEpoch,
      'params': {...params, 'session_id': '$_session', 'engagement_time_msec': ms},
    }),
  );
  // an event nobody can send for days is worthless anyway, so a stuck queue stays small
  if (_queue.length > 500) _queue.removeRange(0, _queue.length - 500);
  unawaited(prefs.setStringList('stats.queue', _queue));
  _timer ??= Timer(const Duration(seconds: 20), _flush);
}

/// 0, 1-9, 10-49 ... so no exact count ever leaves the device
String bucket(int n) => switch (n) {
  0 => '0',
  < 10 => '1-9',
  < 50 => '10-49',
  < 200 => '50-199',
  < 1000 => '200-999',
  _ => '1000+',
};

void trackError(Object e, StackTrace? s, {bool fatal = false}) {
  // the file and line inside the app, never the message, which can hold user text
  final m = RegExp(r'package:spendrix/([\w/]+\.dart)(:\d+)?').firstMatch('$s');
  final where = m == null ? 'unknown' : '${m[1]}${m[2] ?? ''}';
  final type = '${e.runtimeType}';
  // a broken build method throws every frame, one report is enough
  if (statsOn.value == true && _errors.add('$type $where')) {
    track('app_error', {'type': type, 'where': where, 'fatal': '$fatal'});
  }
}

Future<void> _flush() => _sending ??= _send().whenComplete(() => _sending = null);

Future<void> _send() async {
  _timer?.cancel();
  _timer = null;
  // nothing to send, so no stats id gets made either
  if (_queue.isEmpty) return;
  final gen = _generation;
  final Map<String, Object> common;
  try {
    common = _common ?? await _commonFields();
  } catch (_) {
    return;
  }
  // switched off meanwhile, so this id is already forgotten
  if (gen != _generation) return;
  _common = common;
  while (_queue.isNotEmpty && gen == _generation) {
    // GA drops events older than 72 hours
    final cutoff = DateTime.now().subtract(const Duration(hours: 71)).microsecondsSinceEpoch;
    _queue.removeWhere((q) => (jsonDecode(q) as Map)['timestamp_micros'] as int < cutoff);
    final batch = _queue.take(25).toList();
    if (batch.isEmpty) break;
    try {
      final res = await http
          .post(
            Uri.https('www.google-analytics.com', kDebugMode ? '/debug/mp/collect' : '/mp/collect', {
              'measurement_id': _measurementId,
              'api_secret': _apiSecret,
            }),
            // a plain string goes as text/plain, which browsers send without a CORS preflight
            body: jsonEncode({...common, 'events': batch.map(jsonDecode).toList()}),
          )
          .timeout(const Duration(seconds: 20));
      if (kDebugMode) debugPrint('stats: ${res.statusCode} ${res.body}');
      // GA answers 2xx for anything it read; a 4xx won't get better on a retry either
      if (res.statusCode >= 500) break;
    } catch (_) {
      break;
    }
    if (gen != _generation) break;
    _queue.removeRange(0, batch.length);
    await prefs.setStringList('stats.queue', _queue);
  }
}

Future<Map<String, Object>> _commonFields() async {
  var id = prefs.getString('stats.id');
  if (id == null) await prefs.setString('stats.id', id = newId());
  final info = await PackageInfo.fromPlatform();
  final locale = PlatformDispatcher.instance.locale;
  final country = locale.countryCode ?? '';
  final mobile = const {TargetPlatform.android, TargetPlatform.iOS}.contains(defaultTargetPlatform);
  return {
    'client_id': id,
    if (RegExp(r'^[A-Z]{2}$').hasMatch(country)) 'user_location': {'country_id': country},
    'device': {
      'category': mobile ? 'mobile' : 'desktop',
      'operating_system': defaultTargetPlatform.name,
      'language': locale.toLanguageTag(),
    },
    'user_properties': {
      'app_version': {'value': info.version},
      'app_build': {'value': kIsWeb ? 'web' : info.packageName},
    },
  };
}
