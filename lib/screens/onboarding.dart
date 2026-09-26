import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../sync.dart';
import '../widgets.dart';
import 'settings.dart';

/// First run: what Spendrix is, the currency, then cash in hand. Gate moves on once settings exist.
class Onboarding extends StatefulWidget {
  const Onboarding({super.key});

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  bool _pickCurrency = false, _askCash = false, _starting = false;
  String _currency = guessCurrency();
  final _cash = TextEditingController();
  String? _cashError;

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    final cash = parseSigned(_cash.text);
    setState(() => _cashError = cash == null ? 'Type an amount, like 1500' : null);
    if (cash == null) return;
    setState(() => _starting = true);
    try {
      final store = context.read<Store>();
      // before setup, which only seeds what's missing and swaps to Home
      if (cash != 0) await store.save(Account(id: 'acc-cash', name: 'Cash', start: cash));
      await store.setup(_currency);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<Sync>();
    if (!sync.signedIn) {
      if (_askCash) return _cashPage();
      return _pickCurrency ? _currencyPage(canGoBack: true) : _welcomePage();
    }
    // signed in from here: wait for the first pull, then ask for a currency only if the account had none
    if (sync.lastSync != null) return _currencyPage(canGoBack: false);
    return _pullingPage(sync);
  }

  Widget _pullingPage(Sync sync) {
    final problem = sync.busy ? null : sync.problem;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Narrow(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (problem == null) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 24),
                    Text(
                      'Getting your entries',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text('This can take a minute the first time.', textAlign: TextAlign.center),
                  ] else ...[
                    Text(problem.message, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    // retrying can't fix a password problem, Cancel and signing in again can
                    if (!sync.needsPassword) FilledButton(onPressed: sync.syncNow, child: const Text('Try again')),
                  ],
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => sync.signOut(removeData: true), child: const Text('Cancel')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcomePage() {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Narrow(
              width: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/icon/icon.png', width: 96, height: 96, excludeFromSemantics: true),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Spendrix', style: t.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Your money diary. Simple, private, works offline.',
                    style: t.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  for (final (icon, text) in const [
                    (Icons.bolt, 'Add money in and out in seconds'),
                    (Icons.auto_awesome, 'AI help that stays on your device'),
                    (Icons.lock_outline, 'Optional sync, locked with your password'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          IconBubble(icon),
                          const SizedBox(width: 16),
                          Expanded(child: Text(text, style: t.bodyLarge)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => setState(() => _pickCurrency = true),
                    child: const Text('Get started'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => showAccountSheet(context, create: false, fresh: true),
                    child: const Text('I already use Spendrix'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _currencyPage({required bool canGoBack}) => PopScope(
    // back goes to the welcome page instead of closing the app
    canPop: !canGoBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(() => _pickCurrency = false);
    },
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: canGoBack ? BackButton(onPressed: () => setState(() => _pickCurrency = false)) : null,
      ),
      body: SafeArea(
        top: false,
        child: Narrow(
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text('Which currency do you use?', style: Theme.of(context).textTheme.headlineSmall),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text('You can change it later in Settings.'),
              ),
              Expanded(
                child: CurrencyList(selected: _currency, onPick: (c) => setState(() => _currency = c)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  // signed in, the cash comes down with the account
                  onPressed: canGoBack ? () => setState(() => _askCash = true) : (_starting ? null : _start),
                  child: Text(canGoBack ? 'Next' : 'Start'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _cashPage() {
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _askCash = false);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: BackButton(onPressed: () => setState(() => _askCash = false)),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Narrow(
              width: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('How much cash do you have?', style: t.headlineSmall),
                  const SizedBox(height: 4),
                  const Text('Count your wallet so the balance starts right. Leave it empty to start at zero.'),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _cash,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _start(),
                    style: t.headlineSmall,
                    decoration: InputDecoration(
                      labelText: 'Cash in hand',
                      prefixText: '${currencyOf(_currency).symbol} ',
                      errorText: _cashError,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: _starting ? null : _start,
                    child: const Text('Start'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
