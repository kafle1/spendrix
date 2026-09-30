import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../google_auth.dart';
import '../main.dart' show setAppLock;
import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../sync.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entry_form.dart';
import 'guide.dart';

Future<void> openSettings(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(
    settings: const RouteSettings(name: 'settings'),
    builder: (_) => const SettingsScreen(),
  ),
);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _canLock = _lockAvailable();
  final _info = PackageInfo.fromPlatform();
  bool _signingOut = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final sync = context.watch<Sync>();
    final t = Theme.of(context).textTheme;
    final error = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _Header('Sync across devices'),
            if (sync.signedIn) ..._signedIn(store, sync) else _signedOut(),
            const _Header('Money'),
            ListTile(
              leading: const Icon(Icons.currency_exchange),
              title: const Text('Currency'),
              subtitle: Text('${store.currency.name} (${store.currency.code})'),
              onTap: () => _pickCurrency(store),
            ),
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: const Text('Monthly budget'),
              subtitle: Text(store.settings.budget == null ? 'Not set' : store.fmt(store.settings.budget!)),
              onTap: () => _editBudget(store),
            ),
            const _Header('Accounts'),
            for (final a in store.allAccounts)
              ListTile(
                leading: IconBubble(iconOf(a.icon)),
                title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: a.archived ? const Text('Archived') : null,
                trailing: Money(store.balance(a.id)),
                onTap: () => editAccount(context, a),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add account'),
              onTap: () => editAccount(context),
            ),
            const _Header('Categories'),
            for (final kind in const [Kind.expense, Kind.income]) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(kind.label, style: t.labelLarge),
              ),
              for (final c in store.categoriesFor(kind))
                ListTile(
                  leading: IconBubble(iconOf(c.icon)),
                  title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: c.budget == null ? null : Text('Limit ${store.fmt(c.budget!)} a month'),
                  onTap: () => editCategory(context, category: c),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add category'),
                onTap: () => editCategory(context, income: kind == Kind.income),
              ),
            ],
            const _Header('Repeating entries'),
            if (store.recurring.isEmpty)
              const ListTile(
                leading: Icon(Icons.repeat),
                title: Text('Nothing repeats yet'),
                subtitle: Text('Set Repeat in More when adding an entry.'),
              ),
            for (final r in store.recurring) _repeatTile(store, r),
            const _Header('Appearance'),
            ValueListenableBuilder(
              valueListenable: themeMode,
              builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                expandedInsets: const EdgeInsets.symmetric(horizontal: 16),
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => setThemeMode(s.first),
              ),
            ),
            FutureBuilder(
              future: _canLock,
              builder: (context, snap) => snap.data != true
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Header('App lock'),
                        SwitchListTile(
                          secondary: const Icon(Icons.fingerprint),
                          title: const Text('Lock with fingerprint or PIN'),
                          subtitle: const Text('Spendrix asks for it when it opens'),
                          value: prefs.getBool('lock') == true,
                          onChanged: _setLock,
                        ),
                      ],
                    ),
            ),
            const _Header('Your data'),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Back up'),
              subtitle: const Text('Save everything, photos too, in one file'),
              onTap: () => _backup(store),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore'),
              subtitle: const Text('Bring back a backup file'),
              onTap: () => _restore(store),
            ),
            ListTile(
              leading: const Icon(Icons.table_view_outlined),
              title: const Text('Export to a spreadsheet'),
              subtitle: const Text('A CSV file for Excel or Google Sheets'),
              onTap: () => _exportCsv(store),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: error),
              title: Text('Erase everything', style: TextStyle(color: error)),
              onTap: () => _erase(store, sync),
            ),
            const _Header('About'),
            FutureBuilder(
              future: _info,
              builder: (context, snap) => ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Spendrix'),
                subtitle: Text(snap.data == null ? 'Your money diary' : 'Version ${snap.data!.version}'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('How to use Spendrix'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'guide'),
                  builder: (_) => const GuideScreen(),
                ),
              ),
            ),
            if (statsAvailable)
              ValueListenableBuilder(
                valueListenable: statsOn,
                builder: (context, on, _) => SwitchListTile(
                  secondary: const Icon(Icons.insights_outlined),
                  title: const Text('Share anonymous usage stats'),
                  subtitle: const Text(
                    'Which screens get used and when something breaks. Never amounts, names or notes.',
                  ),
                  value: on == true,
                  onChanged: setStats,
                ),
              ),
            const ListTile(leading: Icon(Icons.privacy_tip_outlined), title: Text('No ads. AI runs on your device.')),
          ],
        ),
      ),
    );
  }

  // ---- sync ----

  Widget _signedOut() => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use Spendrix on your phone and computer. Sign in with Google, and your entries are locked '
            'with a private key that only your devices and a hidden folder in your Google Drive hold, '
            'so nobody else can read them, not even us.',
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => showAccountSheet(context), child: const Text('Continue with Google')),
        ],
      ),
    ),
  );

  List<Widget> _signedIn(Store store, Sync sync) {
    final (icon, status) = _status(store, sync);
    final error = Theme.of(context).colorScheme.error;
    return [
      ListTile(
        leading: Icon(icon, color: sync.needsSignIn ? error : null),
        title: Text(sync.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(status),
      ),
      if (sync.needsSignIn)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: FilledButton.icon(
            onPressed: _signingOut ? null : () => _reauth(sync),
            icon: const Icon(Icons.login),
            label: const Text('Continue with Google'),
          ),
        )
      else ...[
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sync now'),
          enabled: !sync.busy && !_signingOut,
          onTap: sync.syncNow,
        ),
        if (sync.onPassword)
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Sync now uses Google'),
            subtitle: const Text('Tap to sign in with Google instead of your password. Nothing uploads again.'),
            enabled: !_signingOut,
            onTap: () => _moveOver(sync),
          ),
      ],
      if (sync.key case final key? when key.isNotEmpty)
        ListTile(
          leading: const Icon(Icons.key),
          title: const Text('Show sync key'),
          subtitle: Text(
            sync.keyInDrive
                ? 'For a new device that asks for it'
                : 'Not in your Google Drive. Keep a copy somewhere safe.',
          ),
          onTap: () => _showKey(context, key),
        ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Sign out'),
        enabled: !_signingOut,
        onTap: () => _signOut(store, sync),
      ),
      ListTile(
        leading: Icon(Icons.delete_forever_outlined, color: error),
        title: Text('Delete account', style: TextStyle(color: error)),
        enabled: !_signingOut,
        onTap: () => _deleteAccount(sync),
      ),
    ];
  }

  (IconData, String) _status(Store store, Sync sync) {
    if (_signingOut) return (Icons.sync, 'Signing out...');
    if (sync.busy) return (Icons.sync, 'Syncing...');
    if (sync.problem case final p?) return (Icons.cloud_off_outlined, p.message);
    final waiting = store.pending;
    if (waiting > 0) {
      return (Icons.cloud_upload_outlined, waiting == 1 ? '1 change waiting' : '$waiting changes waiting');
    }
    if (sync.lastSync case final t?) return (Icons.cloud_done_outlined, 'Synced ${timeAgo(t)}');
    return (Icons.cloud_outlined, 'Not synced yet');
  }

  Future<void> _reauth(Sync sync) async {
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GoogleDialog(
        title: 'Sign in again',
        body:
            'Continue with the Google account you use for Spendrix to keep syncing. '
            'Nothing on this device changes until it works.',
        action: 'Continue with Google',
        run: sync.reauth,
        finish: sync.resume,
      ),
    );
    if (done == true && !sync.keyInDrive && mounted) toast(context, _keyNotInDrive);
  }

  Future<void> _moveOver(Sync sync) async {
    var inDrive = true;
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GoogleDialog(
        title: 'Sync now uses Google',
        body:
            'Pick a Google account to sign in with from now on. Your entries stay locked with the same key, '
            'and Spendrix keeps a copy of it in a hidden folder in your Google Drive so new devices can find it.',
        action: 'Continue with Google',
        run: (g) async {
          inDrive = await sync.moveToGoogle(g);
          return null;
        },
      ),
    );
    if (done != true || !mounted) return;
    toast(
      context,
      inDrive
          ? 'Done. Sync now uses Google.'
          : "Done. Your key didn't reach Google Drive, so use Show sync key to add a new device.",
    );
  }

  Future<void> _deleteAccount(Sync sync) async {
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GoogleDialog(
        title: 'Delete your sync account?',
        body:
            'This deletes your synced copy for good, on every device, and closes the account. '
            'This device keeps its data. Confirm with Google to go ahead.',
        action: 'Delete account',
        destructive: true,
        run: (g) async {
          await sync.deleteAccount(g);
          return null;
        },
      ),
    );
    if (done == true && mounted) toast(context, 'Account deleted. This device keeps its data.');
  }

  Future<void> _signOut(Store store, Sync sync) async {
    if (!await keySaved(context, sync) || !mounted) return;
    final waiting = store.pending;
    final remove = await _choice<bool>(
      context,
      title: 'Sign out?',
      body: [
        'Your synced copy stays in the account. What should happen to the entries on this device?',
        if (waiting > 0)
          "${waiting == 1 ? '1 change hasn\'t' : '$waiting changes haven\'t'} synced yet. "
              "Removing this device's data loses ${waiting == 1 ? 'it' : 'them'}.",
      ].join('\n\n'),
      destructive: ("Remove this device's data", true),
      keep: ("Keep this device's data", false),
    );
    if (remove == null || !mounted) return;
    final nav = Navigator.of(context);
    setState(() => _signingOut = true);
    try {
      await sync.signOut(removeData: remove);
      // an empty device goes back to the welcome screen, which sits under this page
      if (remove) nav.popUntil((r) => r.isFirst);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  // ---- money ----

  Future<void> _pickCurrency(Store store) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: FractionallySizedBox(
          heightFactor: .85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Currency', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    const Text('Amounts stay the same, only the symbol changes.'),
                  ],
                ),
              ),
              Expanded(
                child: CurrencyList(selected: store.settings.currency, onPick: (c) => Navigator.pop(context, c)),
              ),
            ],
          ),
        ),
      ),
    );
    if (code == null || code == store.settings.currency) return;
    await store.save(Settings(currency: code, budget: store.settings.budget));
  }

  Future<void> _editBudget(Store store) async {
    final picked = await showDialog<({int? cents})>(
      context: context,
      builder: (_) => _BudgetDialog(budget: store.settings.budget, symbol: store.currency.symbol),
    );
    if (picked == null) return;
    await store.save(Settings(currency: store.settings.currency, budget: picked.cents));
  }

  // ---- repeating entries ----

  Widget _repeatTile(Store store, Recurring r) {
    String accountName(String? id) => store.account(id)?.name ?? 'Deleted account';
    final (IconData icon, String name) = switch (r.kind) {
      Kind.transfer => (Icons.swap_horiz, '${accountName(r.account)} → ${accountName(r.to)}'),
      Kind.gave || Kind.got => (Icons.person_outline, store.person(r.person)?.name ?? 'Someone'),
      _ => (iconOf(store.category(r.category)?.icon), store.category(r.category)?.name ?? 'Uncategorized'),
    };
    final next = r.nextAfter(dayOf(DateTime.now()));
    final when = !r.active
        ? 'Paused'
        : next == null
        ? 'Ended'
        : 'Next ${dayLabel(next)}';
    return ListTile(
      onTap: () => openEntry(context, repeat: r),
      leading: IconBubble(icon),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Money(r.kind == Kind.transfer ? r.amount : r.amount * r.kind.sign, colored: r.kind != Kind.transfer),
          Text('${r.label} · $when', maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: r.active ? 'Pause' : 'Resume',
            child: Switch(value: r.active, onChanged: (on) => _setActive(store, r, on)),
          ),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _deleteRepeat(r)),
        ],
      ),
    );
  }

  Future<void> _setActive(Store store, Recurring r, bool on) {
    final today = dayOf(DateTime.now());
    // resuming picks up from today instead of adding everything missed while paused
    // ponytail: a monthly repeat on the 29th to 31st can shift to an earlier day here, keep the anchor day if people notice
    final start = on && r.start.isBefore(today)
        ? r.nextAfter(DateTime(today.year, today.month, today.day - 1)) ?? today
        : r.start;
    return store.save(r.copyWith(start: start, active: on));
  }

  Future<void> _deleteRepeat(Recurring r) async {
    final ok = await confirm(
      context,
      title: 'Stop this repeat?',
      body: 'Entries it already added stay.',
      action: 'Delete',
      destructive: true,
    );
    if (ok && mounted) await removeWithUndo(context, [r], 'Repeat deleted');
  }

  // ---- app lock ----

  Future<void> _setLock(bool on) async {
    // turning it off asks too, or anyone holding the unlocked phone could switch it off for later
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: on ? 'Confirm to turn on App lock' : 'Confirm to turn off App lock',
        persistAcrossBackgrounding: true,
      );
      if (!ok) return;
    } on LocalAuthException catch (e) {
      // with the phone's own lock gone there is nothing to check against, so off is the only way out
      final noLock = e.code == LocalAuthExceptionCode.noCredentialsSet;
      if (!(noLock && !on)) {
        if (e.code != LocalAuthExceptionCode.userCanceled && mounted) {
          toast(context, noLock ? 'Set a screen lock on this device first.' : "Couldn't check it's you. Try again.");
        }
        return;
      }
    }
    await setAppLock(on);
    track('feature_used', {'name': on ? 'lock_on' : 'lock_off'});
    if (mounted) setState(() {});
  }

  // ---- your data ----

  Future<void> _backup(Store store) async {
    await _saveFile(
      'spendrix-backup-${_today()}.spendrix',
      await store.backup(),
      'application/octet-stream',
      'Backup saved',
    );
    track('feature_used', {'name': 'backup'});
  }

  Future<void> _exportCsv(Store store) async {
    if (store.entries.isEmpty) {
      toast(context, 'Nothing to export yet. Add an entry first.');
      return;
    }
    // the BOM tells Excel it's UTF-8, so symbols like रु come out right
    await _saveFile('spendrix-${_today()}.csv', utf8.encode('﻿${store.csv()}'), 'text/csv', 'Spreadsheet saved');
    track('feature_used', {'name': 'export_csv'});
  }

  Future<void> _saveFile(String name, Uint8List bytes, String mimeType, String done) async {
    try {
      final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mimeType);
      // the web just downloads it and never says where
      if ((uri != null || kIsWeb) && mounted) toast(context, done);
    } catch (_) {
      if (mounted) toast(context, "Couldn't save the file. Try again.");
    }
  }

  Future<void> _restore(Store store) async {
    final ok = await confirm(
      context,
      title: 'Restore a backup?',
      body:
          'Everything in the file comes back and replaces the same records here. '
          'Anything added after the backup stays.',
      action: 'Choose file',
    );
    if (!ok) return;
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final n = await store.restore(await file.readAsBytes());
      track('feature_used', {'name': 'restore'});
      if (mounted) toast(context, 'Restored $n ${n == 1 ? 'record' : 'records'}');
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (_) {
      if (mounted) toast(context, "Couldn't open that file.");
    }
  }

  Future<void> _erase(Store store, Sync sync) async {
    final synced = sync.signedIn ? ' It also erases them on your other synced devices.' : '';
    if (!await confirm(
      context,
      title: 'Erase everything?',
      body: 'This deletes every entry, account, category, person and repeat.$synced',
      action: 'Erase',
      destructive: true,
    )) {
      return;
    }
    if (!mounted ||
        !await confirm(
          context,
          title: 'Are you sure?',
          body: "This can't be undone. Make a backup first if you might need any of it.",
          action: 'Erase everything',
          destructive: true,
        )) {
      return;
    }
    // pull first, or entries other devices uploaded since the last sync come back after the erase
    if (sync.signedIn) {
      await sync.syncNow();
      if (sync.problem != null) {
        if (mounted) toast(context, "Couldn't reach sync, so nothing was erased. Try again when you're online.");
        return;
      }
    }
    await store.eraseAll();
    // a fresh start shouldn't be tied to the old stats either
    await resetStats();
    if (mounted) toast(context, 'Everything is erased');
  }
}

String _today() => DateTime.now().toIso8601String().substring(0, 10);

Future<bool> _lockAvailable() async {
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) return false;
  try {
    return await LocalAuthentication().isDeviceSupported();
  } catch (_) {
    return false;
  }
}

String _message(Object e) => e is SyncError ? e.message : 'Something went wrong. Try again.';

const _keyNotInDrive = "Your sync key didn't reach Google Drive, so save it from Show sync key to add another device.";

Future<void> _showKey(BuildContext context, List<int> key) {
  final text = showKey(key);
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Your sync key'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'New devices usually find this key in your Google Drive by themselves. If one asks for it, '
              'type or paste it there. Anyone with this key and your Google account can read your entries, '
              'so keep it private.',
            ),
            const SizedBox(height: 16),
            SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) toast(context, 'Sync key copied');
          },
          child: const Text('Copy'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    ),
  );
}

/// Before signing out while Google Drive doesn't hold the key, offers to show it. False means stop.
Future<bool> keySaved(BuildContext context, Sync sync) async {
  final key = sync.key;
  if (sync.keyInDrive || key == null || key.isEmpty) return true;
  final show = await _choice<bool>(
    context,
    title: 'Save your sync key first',
    body:
        "Your sync key isn't in your Google Drive, so this device may hold the only copy. Without it, your "
        'synced entries can\'t be opened on another device. Copy it somewhere safe first.',
    destructive: ('Go on without it', false),
    keep: ('Show sync key', true),
  );
  if (show == null || !context.mounted) return false;
  if (show) await _showKey(context, key);
  return context.mounted;
}

Widget _showHide(bool shown, VoidCallback toggle) => IconButton(
  tooltip: shown ? 'Hide password' : 'Show password',
  icon: Icon(shown ? Icons.visibility_off_outlined : Icons.visibility_outlined),
  onPressed: toggle,
);

/// Cancel, a destructive choice, and a safe choice. Same shape as the sign-out and keep-data prompts.
Future<T?> _choice<T>(
  BuildContext context, {
  required String title,
  required String body,
  required (String, T) destructive,
  required (String, T) keep,
}) => showDialog<T>(
  context: context,
  builder: (context) => AlertDialog(
    scrollable: true,
    title: Text(title),
    content: Text(body),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(
        style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
        onPressed: () => Navigator.pop(context, destructive.$2),
        child: Text(destructive.$1),
      ),
      FilledButton(onPressed: () => Navigator.pop(context, keep.$2), child: Text(keep.$1)),
    ],
  ),
);

/// A money amount field: decimal keyboard, currency prefix, matches the look of every amount input here.
Widget _moneyField(
  TextEditingController controller,
  String symbol, {
  String? label,
  String? hint,
  String? helper,
  int? helperMaxLines,
  String? error,
  int? errorMaxLines,
  bool signed = false,
  bool autofocus = false,
  TextInputAction? textInputAction,
  ValueChanged<String>? onSubmitted,
}) => TextField(
  controller: controller,
  autofocus: autofocus,
  keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
  textInputAction: textInputAction,
  onSubmitted: onSubmitted,
  decoration: InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: '$symbol ',
    helperText: helper,
    helperMaxLines: helperMaxLines,
    errorText: error,
    errorMaxLines: errorMaxLines,
  ),
);

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}

/// Signs in with Google and starts syncing. Returns true once signed in.
/// Call it straight from a tap: on the web the Google popup has to open before anything is awaited.
/// [existing] is "I already use Spendrix": a Google account with no sync asks before starting a new one.
Future<bool> showAccountSheet(BuildContext context, {bool existing = false}) async {
  final google = googleSignIn()..ignore();
  final sync = context.read<Sync>();
  Login? joined;
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _GoogleDialog(
      title: 'Continue with Google',
      body:
          'Pick your Google account. Spendrix keeps your sync key in a hidden folder in your Google Drive, '
          'so your other devices can open your entries.',
      action: 'Continue with Google',
      started: google,
      askIfNew: existing,
      run: sync.google,
      finish: (l) async {
        await sync.start(l);
        joined = l;
      },
    ),
  );
  if (done == true && !sync.keyInDrive && context.mounted) {
    toast(
      context,
      joined?.google.drive == null
          ? 'Google Drive access was off, so use Show sync key to add another device.'
          : _keyNotInDrive,
    );
  }
  return done == true;
}

/// Asks Google who this is, then runs [run]. When [run] hands back a [Login]
/// without its key, asks for the sync key or old password, then [finish]es it.
/// Pops true when everything went through; until then nothing on the device changed.
class _GoogleDialog extends StatefulWidget {
  const _GoogleDialog({
    required this.title,
    required this.body,
    required this.action,
    required this.run,
    this.finish,
    this.started,
    this.destructive = false,
    this.askIfNew = false,
  });

  final String title, body, action;
  final Future<Login?> Function(GoogleTokens g) run;
  final Future<void> Function(Login l)? finish;

  /// a sign-in already running, for when the tap that opened this started it
  final Future<GoogleTokens>? started;
  final bool destructive;

  /// a brand new sync asks first whether this person had an email and password sync before
  final bool askIfNew;

  @override
  State<_GoogleDialog> createState() => _GoogleDialogState();
}

enum _Stage { idle, google, checking, unlock }

class _GoogleDialogState extends State<_GoogleDialog> {
  final _field = TextEditingController(), _email = TextEditingController();
  var _stage = _Stage.idle;
  bool _busy = false, _password = false, _show = false;
  Login? _login;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.started case final f?) _go(f);
  }

  @override
  void dispose() {
    if (_stage == _Stage.google) cancelGoogleSignIn();
    _field.dispose();
    _email.dispose();
    super.dispose();
  }

  /// the old sign-in's email, which can differ from Google's, is only needed before there's an account
  bool get _askEmail => _password && _login?.account == null;

  Future<void> _go(Future<GoogleTokens> google) async {
    setState(() {
      _stage = _Stage.google;
      _error = null;
    });
    try {
      final g = await google;
      if (!mounted) return;
      setState(() => _stage = _Stage.checking);
      final l = await widget.run(g);
      if (!mounted) return;
      if (l == null) return Navigator.pop(context, true);
      if (widget.askIfNew && l.isNew) {
        final sync = context.read<Sync>();
        final old = await _askOld();
        if (old != false) await sync.dropNew(l);
        if (!mounted) return;
        if (old == null) return setState(() => _stage = _Stage.idle);
      }
      if (l.unlocked) return await _finish(l);
      _field.clear();
      _email.text = l.email;
      setState(() {
        _login = l;
        _password = l.account == null;
        _stage = _Stage.unlock;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.idle;
          _error = identical(e, cancelled) ? null : _message(e);
        });
      }
    }
  }

  /// true for "I used email and password", false to start new, null to cancel
  Future<bool?> _askOld() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('No sync on this account'),
      content: const Text(
        'No Spendrix sync on this Google account. Start new, or did you use an email and password before?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('I used email and password')),
        FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Start new')),
      ],
    ),
  );

  Future<void> _finish(Login l) async {
    await widget.finish?.call(l);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final text = _field.text.trim();
    final noEmail = _askEmail && _email.text.trim().isEmpty;
    setState(() {
      _error = noEmail
          ? 'Type the email you used for Spendrix sync before.'
          : text.isEmpty
          ? (_password ? 'Type your old password.' : 'Paste your sync key.')
          : null;
      _busy = _error == null;
    });
    if (!_busy) return;
    final sync = context.read<Sync>();
    try {
      // let "Unlocking..." paint before the slow key stretching starts
      await WidgetsBinding.instance.endOfFrame;
      final l = _login!;
      if (_password) {
        await sync.unlockWithPassword(l, _field.text, email: _askEmail ? _email.text : null);
      } else {
        await sync.unlockWithKey(l, text);
      }
      await _finish(l);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final unlock = _stage == _Stage.unlock;
    final checking = _stage == _Stage.checking || _busy;
    return PopScope(
      // a half-done check could still land after the dialog is gone
      canPop: !checking,
      child: AlertDialog(
        scrollable: true,
        title: Text(unlock ? 'Unlock your entries' : widget.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                !unlock
                    ? widget.body
                    : _login!.account == null && _login!.expect != null
                    ? "This Google account isn't linked to your sync yet. Enter your old Spendrix password once to "
                          'link it, or cancel and pick another Google account.'
                    : _login!.account == null
                    ? 'Enter the email and password you used for Spendrix sync before. You only need them once, '
                          'to link this Google account to your entries.'
                    : _password
                    ? 'Enter the password you used for Spendrix sync before. You only need it once.'
                    : "Your entries are locked with a key this device doesn't have yet. On a device that syncs, "
                          'open Settings and tap Show sync key.',
              ),
              if (unlock) ...[
                const SizedBox(height: 16),
                if (_askEmail) ...[
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    autofocus: _email.text.isEmpty,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Old email'),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _field,
                  enabled: !_busy,
                  autofocus: !_askEmail || _email.text.isNotEmpty,
                  obscureText: _password && !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: _password ? const [AutofillHints.password] : null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _unlock(),
                  decoration: InputDecoration(
                    labelText: _password ? 'Old password' : 'Sync key',
                    suffixIcon: _password ? _showHide(_show, () => setState(() => _show = !_show)) : null,
                  ),
                ),
                if (_login!.account != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _password = !_password;
                              _error = null;
                              _field.clear();
                            }),
                      child: Text(_password ? 'Use sync key instead' : 'Use old password instead'),
                    ),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.error)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: checking
                ? null
                : () {
                    if (_stage == _Stage.google) cancelGoogleSignIn();
                    Navigator.pop(context);
                  },
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: widget.destructive && !unlock
                ? FilledButton.styleFrom(backgroundColor: c.error, foregroundColor: c.onError)
                : null,
            onPressed: unlock
                ? (_busy ? null : _unlock)
                : _stage == _Stage.idle
                // straight from the tap, so a web browser lets the popup open
                ? () => _go(googleSignIn())
                : null,
            child: Text(switch (_stage) {
              _Stage.google => 'Waiting for Google...',
              _Stage.checking => 'Checking...',
              _Stage.unlock => _busy ? 'Unlocking...' : 'Unlock',
              _Stage.idle => widget.action,
            }),
          ),
        ],
      ),
    );
  }
}

/// Monthly budget. Pops (cents: null) to clear it, or null when cancelled.
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.budget, required this.symbol});

  final int? budget;
  final String symbol;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _amount = TextEditingController(text: widget.budget == null ? '' : centsToInput(widget.budget!));
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final text = _amount.text.trim();
    final cents = parseCents(text);
    if (text.isNotEmpty && cents == null) {
      setState(() => _error = 'Type an amount above zero, or leave it empty');
      return;
    }
    Navigator.pop(context, (cents: cents));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Monthly budget'),
    content: _moneyField(
      _amount,
      widget.symbol,
      autofocus: true,
      hint: 'No budget',
      helper: 'The most you want to spend in a month. Leave empty for none.',
      helperMaxLines: 2,
      error: _error,
      errorMaxLines: 2,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

/// Searchable list of currencies with [selected] pinned on top. Needs a bounded height.
class CurrencyList extends StatefulWidget {
  const CurrencyList({super.key, required this.selected, required this.onPick});

  final String selected;
  final ValueChanged<String> onPick;

  @override
  State<CurrencyList> createState() => _CurrencyListState();
}

class _CurrencyListState extends State<CurrencyList> {
  final _search = TextEditingController();

  // fixed on open, so the list doesn't jump around while someone taps through it
  late final _all = [
    ...currencies.where((c) => c.code == widget.selected),
    ...currencies.where((c) => c.code != widget.selected),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final c in _all)
        if ('${c.code} ${c.name} ${c.symbol}'.toLowerCase().contains(q)) c,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search, like rupee or USD'),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Empty(icon: Icons.search_off, title: 'No currency matches that', body: 'Try its code, like NPR.')
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final c = shown[i];
                    final picked = c.code == widget.selected;
                    return ListTile(
                      leading: SizedBox(
                        width: 48,
                        child: Center(child: Text(c.symbol, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ),
                      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(c.code),
                      selected: picked,
                      trailing: picked ? const Icon(Icons.check) : null,
                      onTap: () => widget.onPick(c.code),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---- accounts and categories ----

/// Add ([account] null) or edit an account. Returns the saved account, or null if cancelled.
Future<Account?> editAccount(BuildContext context, [Account? account]) => showModalBottomSheet<Account>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _AccountEditor(account),
);

/// Add or edit a category. Returns the saved category, or null if cancelled.
Future<Category?> editCategory(BuildContext context, {Category? category, bool income = false}) =>
    showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CategoryEditor(category, income: category?.income ?? income),
    );

class _AccountEditor extends StatefulWidget {
  const _AccountEditor(this.account);

  final Account? account;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final _name = TextEditingController(text: widget.account?.name);
  late final _start = TextEditingController(
    text: switch (widget.account?.start ?? 0) {
      0 => '',
      final s => '${s < 0 ? '-' : ''}${centsToInput(s.abs())}',
    },
  );
  late var _icon = widget.account?.icon ?? 'cash';
  late var _archived = widget.account?.archived ?? false;
  String? _nameError, _startError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final start = parseSigned(_start.text);
    setState(() {
      _nameError = name.isEmpty ? 'Give it a name' : null;
      _startError = start == null ? 'Type an amount, like 1500 or -200' : null;
    });
    if (name.isEmpty || start == null || _saving) return;
    _saving = true;
    final a = Account(id: widget.account?.id ?? newId(), name: name, icon: _icon, start: start, archived: _archived);
    await context.read<Store>().save(a);
    if (mounted) Navigator.pop(context, a);
  }

  Future<void> _delete() async {
    final a = widget.account!;
    final ok = await confirm(
      context,
      title: 'Delete ${a.name}?',
      body: 'Entries stay and show "Deleted account".',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    unawaited(removeWithUndo(context, [a], 'Account deleted'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final a = widget.account;
    // entries always need an open account to go to
    final lastOpen = a != null && !a.archived && store.accounts.length <= 1;
    return _Sheet(
      title: a == null ? 'New account' : 'Edit account',
      onSave: _save,
      onDelete: a == null || lastOpen ? null : _delete,
      children: [
        TextField(
          controller: _name,
          autofocus: a == null,
          maxLength: 30,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Name', hintText: 'Like Bank or Wallet', errorText: _nameError),
        ),
        const SizedBox(height: 8),
        _IconGrid(
          names: const ['cash', 'bank', 'wallet', 'card', 'phone', 'savings'],
          selected: _icon,
          onPick: (n) => setState(() => _icon = n),
        ),
        const SizedBox(height: 20),
        _moneyField(
          _start,
          store.currency.symbol,
          signed: true,
          label: 'Starting balance',
          helper: 'What it held before your first entry. Start with - if you owe on it, like a credit card.',
          helperMaxLines: 2,
          error: _startError,
        ),
        if (a != null) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Archive'),
            subtitle: Text(
              lastOpen ? 'Keep at least one account open.' : 'Hide it when adding entries. Its history stays.',
            ),
            value: _archived,
            onChanged: lastOpen ? null : (v) => setState(() => _archived = v),
          ),
        ],
      ],
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor(this.category, {required this.income});

  final Category? category;
  final bool income;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.category?.name);
  late final _budget = TextEditingController(
    text: widget.category?.budget == null ? '' : centsToInput(widget.category!.budget!),
  );
  late var _icon = widget.category?.icon ?? 'other';
  late var _income = widget.income;
  String? _nameError, _budgetError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final text = _budget.text.trim();
    final budget = _income ? null : parseCents(text);
    final badBudget = !_income && text.isNotEmpty && budget == null;
    setState(() {
      _nameError = name.isEmpty ? 'Give it a name' : null;
      _budgetError = badBudget ? 'Type an amount above zero, or leave it empty' : null;
    });
    if (name.isEmpty || badBudget || _saving) return;
    _saving = true;
    final c = Category(id: widget.category?.id ?? newId(), name: name, icon: _icon, income: _income, budget: budget);
    await context.read<Store>().save(c);
    if (mounted) Navigator.pop(context, c);
  }

  Future<void> _delete() async {
    final c = widget.category!;
    final ok = await confirm(
      context,
      title: 'Delete ${c.name}?',
      body: 'Its entries stay and show "Uncategorized".',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    unawaited(removeWithUndo(context, [c], 'Category deleted'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final symbol = context.select<Store, String>((s) => s.currency.symbol);
    return _Sheet(
      title: c == null ? 'New category' : 'Edit category',
      onSave: _save,
      onDelete: c == null ? null : _delete,
      children: [
        if (c == null) ...[
          SegmentedButton<bool>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(value: false, label: Text('Money out')),
              ButtonSegment(value: true, label: Text('Money in')),
            ],
            selected: {_income},
            onSelectionChanged: (s) => setState(() => _income = s.first),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _name,
          autofocus: c == null,
          maxLength: 24,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Name', hintText: 'Like Rent or Pocket money', errorText: _nameError),
        ),
        const SizedBox(height: 8),
        _IconGrid(names: icons.keys, selected: _icon, onPick: (n) => setState(() => _icon = n)),
        if (!_income) ...[
          const SizedBox(height: 20),
          _moneyField(
            _budget,
            symbol,
            label: 'Monthly limit',
            hint: 'Optional',
            helper: 'Spendrix shows how much is left each month.',
            error: _budgetError,
            errorMaxLines: 2,
          ),
        ],
      ],
    );
  }
}

/// The frame of the account and category editors: title, fields, then Delete, Cancel and Save.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children, required this.onSave, this.onDelete});

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 16),
            Row(
              children: [
                if (onDelete != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: error),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(onPressed: onSave, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.names, required this.selected, required this.onPick});

  final Iterable<String> names;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final n in names)
          IconButton(
            tooltip: '${n[0].toUpperCase()}${n.substring(1)}',
            isSelected: n == selected,
            style: IconButton.styleFrom(
              backgroundColor: n == selected ? c.primary : null,
              foregroundColor: n == selected ? c.onPrimary : c.onSurfaceVariant,
            ),
            icon: Icon(iconOf(n)),
            onPressed: () => onPick(n),
          ),
      ],
    );
  }
}
