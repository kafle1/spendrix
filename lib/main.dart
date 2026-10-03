import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai.dart';
import 'legacy.dart';
import 'screens/activity.dart';
import 'screens/assistant.dart';
import 'screens/entry_form.dart';
import 'screens/home.dart';
import 'screens/insights.dart';
import 'screens/onboarding.dart';
import 'screens/people.dart';
import 'store.dart';
import 'stats.dart';
import 'sync.dart';
import 'theme.dart';
import 'update.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  final store = await Store.open();
  startStats(
    () => {
      'entries': bucket(store.entries.length),
      'accounts': bucket(store.accounts.length),
      'people': bucket(store.people.length),
      'currency': store.settings.currency,
      'budget': store.settings.budget != null || store.categories.any((c) => c.budget != null) ? 'yes' : 'no',
      'sync': prefs.getString('sync') != null ? 'on' : 'off',
      'lock': prefs.getBool('lock') == true ? 'on' : 'off',
      'theme': themeMode.value.name,
    },
  );
  currentTab.addListener(() => trackScreen(Shell._tabs[currentTab.value].$3.toLowerCase()));
  await runLegacyImport(store);
  unawaited(checkOtherApp());
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider(create: (_) => Sync(store), lazy: false),
        ChangeNotifierProvider(create: (_) => Assistant(store)),
      ],
      child: const App(),
    ),
  );
  unawaited(checkForUpdate());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: themeMode,
    builder: (context, mode, _) => MaterialApp(
      title: 'Spendrix',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      navigatorObservers: [statsObserver],
      // above the navigator, so the lock also covers a page opened on top of Home
      builder: (context, child) => _Lock(child: child!),
      home: const Gate(),
    ),
  );
}

/// Onboarding first, then the app.
class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) {
    final resets = context.select<Store, int>((s) => s.resets);
    return context.select<Store, bool>((s) => s.onboarded) ? Shell(key: ValueKey(resets)) : const Onboarding();
  }
}

/// The app lock, when on. The app stays built underneath so unlocking returns to the same page.
class _Lock extends StatefulWidget {
  const _Lock({required this.child});

  final Widget child;

  @override
  State<_Lock> createState() => _LockState();
}

/// Turns the app lock on or off.
Future<void> setAppLock(bool on) async {
  await prefs.setBool('lock', on);
  await _secureWindow(on);
}

Future<void> _secureWindow(bool on) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await const MethodChannel('spendrix/secure').invokeMethod<void>('set', on);
  }
}

class _LockState extends State<_Lock> {
  bool _locked = prefs.getBool('lock') == true, _covered = false;
  DateTime? _awaySince;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      // inactive is both a phone leaving for another app and a desktop window losing focus
      onInactive: () => _awaySince ??= DateTime.now(),
      onResume: () {
        // a short trip to another app (the camera, a share sheet) doesn't lock
        final since = _awaySince;
        _awaySince = null;
        final away = since == null ? Duration.zero : DateTime.now().difference(since);
        // abs, so turning the clock back still locks but a tiny automatic clock fix doesn't
        if (prefs.getBool('lock') == true && !_locked && away.abs() > const Duration(seconds: 30)) {
          setState(() => _locked = true);
          _unlock();
        }
      },
      // iOS snapshots the screen for the app switcher on the way out, so hide it first
      onStateChange: (state) {
        final covered =
            defaultTargetPlatform == TargetPlatform.iOS &&
            prefs.getBool('lock') == true &&
            state != AppLifecycleState.resumed;
        if (covered != _covered) setState(() => _covered = covered);
      },
    );
    if (_locked) {
      unawaited(_secureWindow(true));
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    var ok = false;
    try {
      ok = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock Spendrix',
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      if (e.code == LocalAuthExceptionCode.noCredentialsSet) {
        // the phone's own screen lock was removed, so this lock can never open again
        await setAppLock(false);
        ok = true;
      }
    }
    if (!ok || !mounted) return;
    // the pin screen hides the app, so coming back from it isn't time away
    _awaySince = null;
    setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final hide = _locked || _covered;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: hide,
          child: Offstage(offstage: hide, child: widget.child),
        ),
        if (hide) _LockScreen(onUnlock: _unlock),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Empty(
      icon: Icons.lock_outline,
      title: 'Spendrix is locked',
      body: 'Unlock with your fingerprint, face or phone PIN.',
      action: FilledButton.icon(onPressed: onUnlock, icon: const Icon(Icons.lock_open), label: const Text('Unlock')),
    ),
  );
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  static const _pages = [HomeScreen(), ActivityScreen(), AssistantScreen(), InsightsScreen(), PeopleScreen()];
  static const _tabs = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Activity'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Ask'),
    (Icons.pie_chart_outline, Icons.pie_chart, 'Insights'),
    (Icons.people_outline, Icons.people, 'People'),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: currentTab,
    builder: (context, tab, _) {
      final wide = MediaQuery.sizeOf(context).width >= 800;
      final body = _FadeStack(index: tab, children: _pages);
      void pick(int i) {
        if (i != tab) HapticFeedback.selectionClick();
        currentTab.value = i;
      }

      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => openEntry(context),
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => openEntry(context),
        },
        child: Focus(
          autofocus: true,
          child: PopScope(
            // back on another tab goes Home first instead of closing the app
            canPop: tab == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) currentTab.value = 0;
            },
            child: Scaffold(
              body: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: tab,
                          onDestinationSelected: pick,
                          labelType: NavigationRailLabelType.all,
                          groupAlignment: -.85,
                          destinations: [
                            for (final (icon, selected, label) in _tabs)
                              NavigationRailDestination(
                                icon: Icon(icon),
                                selectedIcon: Icon(selected),
                                label: Text(label),
                              ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: body),
                      ],
                    )
                  : body,
              bottomNavigationBar: wide
                  ? null
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Divider(),
                        NavigationBar(
                          selectedIndex: tab,
                          onDestinationSelected: pick,
                          destinations: [
                            for (final (icon, selected, label) in _tabs)
                              NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );
}

/// An IndexedStack that fades the new tab in, so every tab keeps its state and scroll position.
class _FadeStack extends StatefulWidget {
  const _FadeStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_FadeStack> createState() => _FadeStackState();
}

class _FadeStackState extends State<_FadeStack> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  late final _curve = CurvedAnimation(parent: _fade, curve: Curves.easeOut);

  @override
  void didUpdateWidget(_FadeStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: IndexedStack(index: widget.index, children: widget.children),
  );
}
