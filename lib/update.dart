import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_io.dart' if (dart.library.js_interop) 'update_web.dart';

/// The version of a newer release than the one running, once [checkForUpdate] finds one.
final update = ValueNotifier<String?>(null);

/// The file Update downloads and checks. Unused on web and iPhone, which can't install a file themselves.
({Uri url, String digest, String name})? _asset;

/// What the card shows while it works. A null progress with busy set is a moving bar.
final _job = ValueNotifier<({bool busy, double? progress, String? note})>((busy: false, progress: null, note: null));

const _ours = 'https://github.com/kafle1/spendrix/';
const _android = MethodChannel('spendrix/update');

AppLifecycleListener? _lifecycle;
DateTime? _checked;
String? _shown;
http.Client? _client;
var _cancelled = false;

/// Looks for a newer release on launch and whenever the app comes back, at most once an hour.
/// Any failure just means no update card.
Future<void> checkForUpdate() async {
  if (_lifecycle == null) {
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(checkForUpdate()));
    // a download the app was killed in the middle of, or an installed update
    if (!kIsWeb) {
      try {
        await (await _dir()).delete(recursive: true);
      } catch (_) {}
    }
  }
  final now = DateTime.now();
  if (_job.value.busy || (_checked != null && now.difference(_checked!) < const Duration(hours: 1))) return;
  _checked = now;
  try {
    final info = await PackageInfo.fromPlatform();
    await (kIsWeb ? _checkWeb(info) : _checkGithub(info));
  } catch (e) {
    // offline or timed out, so the next resume tries again
    _checked = null;
    debugPrint('update check failed: $e');
  }
}

Future<void> _checkGithub(PackageInfo info) async {
  final res = await http
      .get(Uri.parse('https://api.github.com/repos/kafle1/spendrix/releases/latest'))
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return;
  final release = jsonDecode(res.body) as Map<String, dynamic>;
  final latest = (release['tag_name'] as String).replaceFirst(RegExp('^v'), '');
  if (!_newer(latest, info.version) || _dismissed(latest)) return;
  if (Platform.isIOS) return _show(latest, latest);
  final name = _file(info.packageName);
  final asset = (release['assets'] as List).cast<Map<String, dynamic>>().where((a) => a['name'] == name).firstOrNull;
  final url = asset?['browser_download_url'] as String?;
  final digest = (asset?['digest'] as String?)?.toLowerCase();
  // never download anything that isn't ours or can't be checked
  if (url == null || !url.startsWith(_ours) || digest == null || !digest.startsWith('sha256:')) return;
  _asset = (url: Uri.parse(url), digest: digest, name: name!);
  _show(latest, latest);
}

/// The web app is just files on the server, so a newer version.json means a refresh gets the new one.
Future<void> _checkWeb(PackageInfo info) async {
  final stamp = '${DateTime.now().millisecondsSinceEpoch}';
  final res = await http
      .get(appBase().resolve('version.json').replace(queryParameters: {'t': stamp}))
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return;
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final version = '${j['version']}', build = int.tryParse('${j['build_number']}') ?? 0;
  final newer =
      _newer(version, info.version) || (version == info.version && build > (int.tryParse(info.buildNumber) ?? 0));
  final key = '$version+$build';
  if (!newer || _dismissed(key)) return;
  _show(key, version);
}

/// Whether the user closed the card for this version already.
bool _dismissed(String key) => key == _shown && update.value == null;

void _show(String key, String version) {
  if (key != _shown) _say(null);
  _shown = key;
  update.value = version;
}

void _say(String? note) => _job.value = (busy: false, progress: null, note: note);

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

/// The release file that installs over this copy. On Android that means the same app id.
String? _file(String id) {
  // 1.2 and older installed as com.example.expenses_tracker, 1.3 to 2.0.1 as com.spendrix
  if (Platform.isAndroid) return id == 'com.spendrix' ? 'Spendrix-android-for-1.3-and-2.0.apk' : 'Spendrix-android.apk';
  if (Platform.isMacOS) return 'Spendrix-macos.dmg';
  if (Platform.isWindows) return 'Spendrix-windows.zip';
  // Platform.version ends like: on "linux_x64"
  if (Platform.isLinux && Platform.version.endsWith('_x64"')) return 'Spendrix-linux-x64.tar.gz';
  return null;
}

/// Opens [url] in the browser. False when none opened.
Future<bool> openUpdate(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((Object _) => false);

// per user on every platform, unlike linux's shared /tmp
Future<Directory> _dir() async => Directory('${(await getApplicationCacheDirectory()).path}/spendrix-update');

Future<void> _install() async {
  final version = update.value, a = _asset;
  if (version == null || a == null || _job.value.busy) return;
  // set before the first await, so a second tap can't start another download
  _job.value = (busy: true, progress: null, note: null);
  final home = File(Platform.resolvedExecutable).parent;
  try {
    // asked before downloading, since android may restart the app while the user is in settings
    if (Platform.isAndroid && await _android.invokeMethod<bool>('canInstall') != true) {
      _say('Allow Spendrix to install apps, then come back and tap Update.');
      return await _android.invokeMethod('allow');
    }
    if ((Platform.isWindows || Platform.isLinux) && !await _canReplace(home)) {
      return _say("Spendrix can't write to its own folder. Get the new version from spendrix.web.app.");
    }
    final file = await _download(a);
    if (file == null) return;
    if (Platform.isMacOS) return await _openDmg(file, version);
    if (!Platform.isAndroid) return await _swap(file, home);
    await _android.invokeMethod('install', file.path);
    // same signing key, so Android keeps all the data
    _say('Tap Install to finish. Your data stays.');
  } catch (e) {
    debugPrint('update failed: $e');
    _say("Couldn't update. Try again");
  }
}

/// Streams the release file into the cache and checks its SHA-256. Null when it failed or was cancelled.
Future<File?> _download(({Uri url, String digest, String name}) a) async {
  final dir = await _dir();
  final file = File('${dir.path}/${a.name}');
  final client = _client = http.Client();
  _cancelled = false;
  // again, now that there's a client for Cancel to close
  _job.value = (busy: true, progress: null, note: null);
  try {
    await dir.create(recursive: true);
    // starts at our github url; http follows its redirect to github's file host
    final res = await client.send(http.Request('GET', a.url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw HttpException('download answered ${res.statusCode}');
    final total = res.contentLength ?? 0;
    final hash = const DartSha256().newHashSink();
    final out = file.openWrite();
    var got = 0, shown = -1;
    try {
      await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
        out.add(chunk);
        hash.add(chunk);
        got += chunk.length;
        final pct = total > 0 ? got * 100 ~/ total : -1;
        if (pct != shown && pct >= 0) {
          shown = pct;
          _job.value = (busy: true, progress: pct / 100, note: null);
        }
      }
    } finally {
      await out.close();
    }
    // a Cancel that landed after the last chunk
    if (_cancelled) throw const HttpException('cancelled');
    hash.close();
    final hex = (await hash.hash()).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if ('sha256:$hex' == a.digest) return file;
    _say("The download didn't check out. Try again");
  } catch (e) {
    debugPrint('update download failed: $e');
    _say(
      _cancelled
          ? null
          : e is FileSystemException
          ? "Couldn't save the update. Free up some space and try again."
          : "Couldn't download. Try again",
    );
  } finally {
    client.close();
    _client = null;
  }
  await file.delete().catchError((Object _) => file);
  return null;
}

void _cancel() {
  _cancelled = true;
  _client?.close();
}

/// The mac app is sandboxed, so it can't replace itself. It puts the dmg in Downloads and opens it.
Future<void> _openDmg(File dmg, String version) async {
  final downloads = await getDownloadsDirectory();
  if (downloads == null) throw const FileSystemException('no Downloads folder');
  final out = await dmg.copy('${downloads.path}/Spendrix-$version.dmg');
  await dmg.delete();
  if (!await launchUrl(Uri.file(out.path))) throw FileSystemException('could not open', out.path);
  _say('Quit Spendrix, then drag the new one from the window that opened into Applications.');
}

/// A Flutter bundle folder this user can write to, so a copy over it works without admin rights.
Future<bool> _canReplace(Directory home) async {
  if (!await Directory('${home.path}/data/flutter_assets').exists()) return false;
  final probe = File('${home.path}/.spendrix-update-check');
  try {
    await probe.writeAsString('');
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// Starts a helper that waits for this app to quit, unpacks the update over [home] and opens it again.
Future<void> _swap(File archive, Directory home) async {
  final exe = Platform.resolvedExecutable;
  _job.value = (busy: true, progress: null, note: 'Restarting on the new version');
  if (Platform.isWindows) {
    final script = await File('${archive.parent.path}/swap.ps1').writeAsString(_windowsSwap);
    await Process.start('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
      '$pid',
      archive.path,
      home.path,
      exe,
    ], mode: ProcessStartMode.detached);
  } else {
    await Process.start('/bin/sh', [
      '-c',
      _linuxSwap,
      'sh',
      '$pid',
      archive.path,
      home.path,
      exe,
    ], mode: ProcessStartMode.detached);
  }
  await Hive.close().catchError((Object _) {});
  exit(0);
}

// copies over without /MIR: someone may have unzipped straight into a folder with their own files in it
const _windowsSwap = r'''
param($AppPid, $Zip, $Dir, $Exe)
Wait-Process -Id $AppPid -Timeout 30 -ErrorAction SilentlyContinue
$new = Join-Path ([IO.Path]::GetTempPath()) 'spendrix-new'
Remove-Item $new -Recurse -Force -ErrorAction SilentlyContinue
try {
  Expand-Archive -LiteralPath $Zip -DestinationPath $new -Force -ErrorAction Stop
  robocopy $new $Dir /E /R:10 /W:1 /NFL /NDL /NJH /NJS | Out-Null
} catch {}
Remove-Item $new, $Zip -Recurse -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $Exe
''';

// gives up waiting after 30s, in case the launcher never reaps the old process
const _linuxSwap = r'''
i=0
while kill -0 "$1" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done
new=$(mktemp -d) && tar -xzf "$2" -C "$new" && cp -rf "$new"/. "$3"/
rm -rf "$new" "$2"
exec "$4"
''';

void _go() {
  if (kIsWeb) return reloadPage();
  if (Platform.isIOS) {
    return unawaited(
      openUpdate('${_ours}releases/latest').then((ok) => ok ? null : _say("Couldn't open the release page")),
    );
  }
  unawaited(_install());
}

void _dismiss() {
  _say(null);
  update.value = null;
}

String _line() {
  if (kIsWeb) return 'Tap Refresh to load it.';
  if (Platform.isIOS) return "iPhone apps can't update themselves. Get it from the release page.";
  if (Platform.isAndroid) return 'Tap Update, then Install. Your data stays.';
  if (Platform.isMacOS) return 'Tap Update to download it. Your data stays.';
  return 'Spendrix restarts on the new version. Your data stays.';
}

/// The update card. Shows nothing until [checkForUpdate] finds a newer version.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([update, _job]),
    builder: (context, _) {
      final version = update.value;
      if (version == null) return const SizedBox.shrink();
      final job = _job.value;
      final c = Theme.of(context).colorScheme, t = Theme.of(context).textTheme;
      return Card(
        color: c.surfaceContainerLow,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kIsWeb ? 'A new Spendrix is ready' : 'Spendrix $version is ready', style: t.titleSmall),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(job.note ?? _line(), style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
              ),
              if (job.busy)
                Padding(
                  padding: const EdgeInsets.only(top: 12, right: 8),
                  child: LinearProgressIndicator(value: job.progress),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Cancel only does something while a download runs
                  TextButton(
                    onPressed: job.busy ? (_client == null ? null : _cancel) : _dismiss,
                    child: Text(job.busy ? 'Cancel' : 'Not now'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: job.busy ? null : _go,
                    child: Text(kIsWeb ? 'Refresh' : (Platform.isIOS ? 'Open' : 'Update')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
