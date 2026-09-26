import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// A newer release than the one running, once [checkForUpdate] finds one.
final update = ValueNotifier<({String version, String url})?>(null);

/// Asks GitHub for the latest release. Any failure just means no update card.
Future<void> checkForUpdate() async {
  // the web version is always the newest one
  if (kIsWeb) return;
  try {
    final res = await http
        .get(Uri.parse('https://api.github.com/repos/kafle1/spendrix/releases/latest'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return;
    final release = jsonDecode(res.body) as Map<String, dynamic>;
    final latest = (release['tag_name'] as String).replaceFirst(RegExp('^v'), '');
    final info = await PackageInfo.fromPlatform();
    if (!_newer(latest, info.version)) return;
    final name = _file(info.packageName);
    final asset = (release['assets'] as List).cast<Map<String, dynamic>>().where((a) => a['name'] == name);
    update.value = (
      version: latest,
      url: (asset.isEmpty ? release['html_url'] : asset.first['browser_download_url']) as String,
    );
  } catch (e) {
    debugPrint('update check failed: $e');
  }
}

/// Whether version [a] is above [b], comparing 2.0.10 above 2.0.9.
bool _newer(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split(RegExp('[+-]')).first.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < max(x.length, y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

/// The release file that installs over this copy. On Android that means the same app id and chip.
String? _file(String id) {
  // Platform.version ends like: on "android_arm64"
  final chip = RegExp(r'_(\w+)"$').firstMatch(Platform.version)?.group(1);
  if (Platform.isAndroid) {
    final abi = switch (chip) {
      'arm64' => '',
      'arm' => '-32bit',
      'x64' => '-x86_64',
      _ => null,
    };
    // 1.2 and older installed as com.example.expenses_tracker, 1.3 to 2.0.1 as com.spendrix
    return abi == null ? null : 'Spendrix-android$abi${id == 'com.spendrix' ? '-for-1.3-and-2.0' : ''}.apk';
  }
  if (Platform.isMacOS) return 'Spendrix-macos.dmg';
  if (Platform.isWindows) return 'Spendrix-windows.zip';
  if (Platform.isLinux && chip == 'x64') return 'Spendrix-linux-x64.tar.gz';
  return null;
}

/// Opens the download in the browser, which installs it from there. False when no browser opened.
Future<bool> openUpdate(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((Object _) => false);
