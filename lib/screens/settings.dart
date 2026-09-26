import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../format.dart';
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
            'Use Spendrix on your phone and computer. Your entries are locked with your password '
            'before they leave this device, so nobody else can read them, not even us.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => showAccountSheet(context, create: true),
                child: const Text('Create account'),
              ),
              OutlinedButton(onPressed: () => showAccountSheet(context, create: false), child: const Text('Sign in')),
            ],
          ),
        ],
      ),
    ),
  );

  List<Widget> _signedIn(Store store, Sync sync) {
    final (icon, status) = _status(store, sync);
    final error = Theme.of(context).colorScheme.error;
    return [
      ListTile(
        leading: Icon(icon, color: sync.needsPassword ? error : null),
        title: Text(sync.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(status),
      ),
      if (sync.needsPassword)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: FilledButton.icon(
            onPressed: _signingOut ? null : () => _reauth(sync),
            icon: const Icon(Icons.key),
            label: const Text('Enter your password'),
          ),
        )
      else
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sync now'),
          enabled: !sync.busy && !_signingOut,
          onTap: sync.syncNow,
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

  Future<void> _reauth(Sync sync) => showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(
      title: 'Enter your password',
      body:
          'Sign in again as ${sync.email} to keep syncing. Forgot it? Sign out and keep '
          "this device's data, then create a new account.",
      action: 'Sign in',
      busyLabel: 'Checking password...',
      run: sync.reauth,
    ),
  );

  Future<void> _deleteAccount(Sync sync) async {
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswordDialog(
        title: 'Delete your sync account?',
        body:
            'This deletes your synced copy for good, on every device, and closes the account. '
            'This device keeps its data.',
        action: 'Delete account',
        busyLabel: 'Deleting...',
        destructive: true,
        run: sync.deleteAccount,
      ),
    );
    if (done == true && mounted) toast(context, 'Account deleted. This device keeps its data.');
  }

  Future<void> _signOut(Store store, Sync sync) async {
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

/// Create a sync account or sign in, then start syncing. Returns true once signed in.
/// [fresh] is for a device with nothing on it yet: it just fills up from the account.
Future<bool> showAccountSheet(BuildContext context, {required bool create, bool fresh = false}) async {
  final sync = context.read<Sync>();
  final picked = await showDialog<(Session, bool)>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SyncAccountForm(create: create, fresh: fresh),
  );
  if (picked == null) return false;
  final (session, keepLocal) = picked;
  unawaited(sync.start(session, keepLocal: keepLocal));
  return true;
}

class _SyncAccountForm extends StatefulWidget {
  const _SyncAccountForm({required this.create, required this.fresh});

  final bool create, fresh;

  @override
  State<_SyncAccountForm> createState() => _SyncAccountFormState();
}

class _SyncAccountFormState extends State<_SyncAccountForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _show = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  String? _check() {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      return "That email address doesn't look right.";
    }
    if (_password.text.isEmpty) return 'Type your password.';
    if (!widget.create) return null;
    if (_password.text.length < 10) return 'Use at least 10 characters.';
    if (_repeat.text != _password.text) return "The two passwords don't match.";
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = _check();
    setState(() {
      _error = problem;
      _busy = problem == null;
    });
    if (problem != null) return;
    final sync = context.read<Sync>();
    final store = context.read<Store>();
    try {
      // let "Checking password..." paint before the slow key stretching starts
      await WidgetsBinding.instance.endOfFrame;
      final s = await sync.signIn(_email.text, _password.text, create: widget.create);
      if (!mounted) return;
      final keepLocal = widget.create
          ? true
          : widget.fresh || !store.hasOwnData
          ? false
          : await _askKeep();
      if (keepLocal == null || !mounted) return;
      TextInput.finishAutofillContext();
      Navigator.pop(context, (s, keepLocal));
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _askKeep() => _choice<bool>(
    context,
    title: 'This device already has entries',
    body:
        'Add them to the account to keep everything together. '
        "Or replace them with the account's data, which removes this device's entries.",
    destructive: ("Replace with the account's data", false),
    keep: ("Add this device's data to the account", true),
  );

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return PopScope(
      // leaving halfway could make an account nobody finishes setting up
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(widget.create ? 'Create account' : 'Sign in'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _email,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: [widget.create ? AutofillHints.newPassword : AutofillHints.password],
                  textInputAction: widget.create ? TextInputAction.next : TextInputAction.done,
                  onSubmitted: widget.create ? null : (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: widget.create ? 'At least 10 characters' : null,
                    suffixIcon: _showHide(_show, () => setState(() => _show = !_show)),
                  ),
                ),
                if (widget.create) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _repeat,
                    enabled: !_busy,
                    obscureText: !_show,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'Repeat password'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 20, color: c.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Spendrix can't reset this password. If you forget it, your synced copy can't be opened, "
                          'but this device keeps its data.',
                          style: t.bodySmall,
                        ),
                      ),
                    ],
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
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy
                  ? 'Checking password...'
                  : widget.create
                  ? 'Create account'
                  : 'Sign in',
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for the sync password, then runs [run] with it. Pops true when [run] finished.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.body,
    required this.action,
    required this.busyLabel,
    required this.run,
    this.destructive = false,
  });

  final String title, body, action, busyLabel;
  final Future<void> Function(String password) run;
  final bool destructive;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  bool _show = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final empty = _password.text.isEmpty;
    setState(() {
      _error = empty ? 'Type your password.' : null;
      _busy = !empty;
    });
    if (empty) return;
    try {
      await WidgetsBinding.instance.endOfFrame;
      await widget.run(_password.text);
      if (mounted) Navigator.pop(context, true);
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
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.body),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !_busy,
                autofocus: true,
                obscureText: !_show,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: _showHide(_show, () => setState(() => _show = !_show)),
                ),
              ),
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
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: widget.destructive
                ? FilledButton.styleFrom(backgroundColor: c.error, foregroundColor: c.onError)
                : null,
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? widget.busyLabel : widget.action),
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
