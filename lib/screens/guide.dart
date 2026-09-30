import 'package:flutter/material.dart';

import '../widgets.dart';

/// A short how-to, opened from Settings.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static const _sections = [
    (
      Icons.add_circle_outline,
      'Adding money in and out',
      'Tap + and type the amount. Pick Money out or Money in, choose a category, and save. '
          'Tap any entry later to change or delete it.',
    ),
    (
      Icons.swap_horiz,
      'Transfers',
      'Moving money between your own accounts, like cash to bank, is a transfer. '
          "It changes both balances but doesn't count as spending or income.",
    ),
    (
      Icons.people_outline,
      'Lending and borrowing',
      'Use You gave and You got when you lend or borrow. The People tab shows who owes you and whom you owe, '
          'and you can settle up anytime.',
    ),
    (
      Icons.repeat,
      'Repeating entries',
      'For rent, salary or bills, open More when adding an entry and set Repeat. '
          "Spendrix adds each one when it's due, the next time you open the app. Pause or delete it in Settings.",
    ),
    (
      Icons.auto_awesome_outlined,
      'Ask, speak or snap',
      'In the Ask tab, type or tap the mic and say "khana 450" in Nepali or English, or take a photo of a bill. '
          'Spendrix writes the entry for you to check and save. You can also ask "How much did I spend on food this month?" '
          'The AI downloads once, then works offline. Your voice, photos and entries never leave your device.',
    ),
    (
      Icons.savings_outlined,
      'Budgets',
      'Set a monthly budget in Settings, and a limit for any money-out category. '
          'Spendrix shows how much is left for the month.',
    ),
    (
      Icons.sync,
      'Sync with Google',
      'Sync is optional. In Settings, tap Continue with Google. Your entries are locked with a private key '
          'before they leave this device, and only your devices hold it, so nobody else can read them. '
          'The key waits in a hidden folder in your Google Drive, so your other devices find it by themselves.',
    ),
    (
      Icons.backup_outlined,
      'Backups',
      'In Settings, Back up saves everything into one file, photos included. '
          'Keep it somewhere safe, and use Restore to bring it back on any device.',
    ),
    (
      Icons.fingerprint,
      'App lock',
      'Turn on App lock in Settings to ask for your fingerprint, face or phone PIN when Spendrix opens. '
          "It locks again after you've been away for 30 seconds.",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('How to use Spendrix')),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final (icon, title, body) in _sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconBubble(icon),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(header: true, child: Text(title, style: t.titleMedium)),
                          const SizedBox(height: 4),
                          Text(body, style: t.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
