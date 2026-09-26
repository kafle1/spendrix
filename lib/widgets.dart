import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'format.dart';
import 'models.dart';
import 'screens/entry_form.dart';
import 'store.dart';
import 'theme.dart';

/// icon names stored on accounts and categories
const icons = <String, IconData>{
  'cash': Icons.payments_outlined,
  'bank': Icons.account_balance_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'card': Icons.credit_card,
  'phone': Icons.smartphone,
  'savings': Icons.savings_outlined,
  'food': Icons.restaurant_outlined,
  'groceries': Icons.local_grocery_store_outlined,
  'coffee': Icons.local_cafe_outlined,
  'transport': Icons.directions_bus_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'travel': Icons.flight_outlined,
  'bills': Icons.receipt_long_outlined,
  'internet': Icons.wifi,
  'shopping': Icons.shopping_bag_outlined,
  'clothes': Icons.checkroom_outlined,
  'health': Icons.medical_services_outlined,
  'beauty': Icons.spa_outlined,
  'fun': Icons.celebration_outlined,
  'sports': Icons.sports_soccer_outlined,
  'education': Icons.school_outlined,
  'kids': Icons.child_care_outlined,
  'pets': Icons.pets_outlined,
  'home': Icons.home_outlined,
  'repair': Icons.build_outlined,
  'insurance': Icons.shield_outlined,
  'tax': Icons.gavel_outlined,
  'charity': Icons.volunteer_activism_outlined,
  'subscriptions': Icons.subscriptions_outlined,
  'salary': Icons.work_outline,
  'business': Icons.storefront_outlined,
  'gift': Icons.card_giftcard,
  'investment': Icons.trending_up,
  'other': Icons.category_outlined,
};

IconData iconOf(String? name) => icons[name] ?? Icons.category_outlined;

/// a labeled value in a row of stats, e.g. "You'll get / Rs 500"
Widget statColumn(BuildContext context, String label, Widget value, {TextStyle? valueStyle}) => Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      DefaultTextStyle.merge(style: valueStyle ?? Theme.of(context).textTheme.titleMedium, child: value),
    ],
  ),
);

/// the selected tab of the main screen, so any screen can jump to another tab
final currentTab = ValueNotifier(0);

/// An amount in the user's currency, with tabular digits so columns line up.
/// With [colored], money in is green with "+" and money out red with "−".
class Money extends StatelessWidget {
  const Money(this.cents, {super.key, this.style, this.colored = false});

  final int cents;
  final TextStyle? style;
  final bool colored;

  @override
  Widget build(BuildContext context) {
    final cur = context.select<Store, Currency>((s) => s.currency);
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text(
      money(cents, cur, sign: colored),
      style: base.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        color: colored ? moneyColor(context, cents) : null,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class IconBubble extends StatelessWidget {
  const IconBubble(this.icon, {super.key, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.secondaryContainer, shape: BoxShape.circle),
      child: Icon(icon, size: size * .5, color: c.onSecondaryContainer),
    );
  }
}

/// One row of history. Tap opens it for editing.
class EntryTile extends StatelessWidget {
  const EntryTile(this.entry, {super.key, this.showDate = false});

  final Entry entry;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final store = context.read<Store>();
    final e = entry;
    String accountName(String? id) => store.account(id)?.name ?? 'Deleted account';
    final (IconData icon, String title, String detail) = switch (e.kind) {
      Kind.transfer => (Icons.swap_horiz, 'Transfer', '${accountName(e.account)} → ${accountName(e.to)}'),
      Kind.gave || Kind.got => (
        Icons.person_outline,
        store.person(e.person)?.name ?? 'Someone',
        '${e.kind.label} · ${accountName(e.account)}',
      ),
      _ => (
        iconOf(store.category(e.category)?.icon),
        store.category(e.category)?.name ?? 'Uncategorized',
        accountName(e.account),
      ),
    };
    final subtitle = [
      ?e.paidIn(store.currency),
      if (e.note.isNotEmpty) e.note,
      if (showDate) dayLabel(e.date),
      detail,
    ].join(' · ');
    return ListTile(
      leading: IconBubble(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (e.recurring != null) const Icon(Icons.repeat, size: 16, semanticLabel: 'Repeats'),
          if (e.photo) const Icon(Icons.image_outlined, size: 16, semanticLabel: 'Has a photo'),
          const SizedBox(width: 6),
          Money(
            e.kind == Kind.transfer ? e.amount : e.signed,
            colored: e.kind != Kind.transfer,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
      onTap: () => openEntry(context, entry: e),
    );
  }
}

/// what an empty list shows instead of a blank screen
class Empty extends StatelessWidget {
  const Empty({super.key, required this.icon, required this.title, this.body, this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!, style: t.bodyMedium, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Centers content at a readable width on tablets and desktops.
class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.child, this.width = 720});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? body,
  required String action,
  bool destructive = false,
}) async {
  final c = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: c.error, foregroundColor: c.onError) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void toast(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// Deletes [models] and offers Undo for a few seconds. Undo saves them again,
/// which also brings them back on synced devices.
Future<void> removeWithUndo(BuildContext context, List<Model> models, String message) async {
  final store = context.read<Store>();
  final messenger = ScaffoldMessenger.of(context);
  await store.remove([for (final m in models) m.id]);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.saveAll(models)),
      ),
    );
}
