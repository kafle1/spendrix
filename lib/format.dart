import 'dart:ui';

import 'package:intl/intl.dart';

class Currency {
  const Currency(this.code, this.symbol, this.name, {this.indian = false});
  final String code, symbol, name;

  /// groups as 1,20,000 instead of 120,000
  final bool indian;

  /// "Rs " but "$" and "A$", so the digits sit right after it
  String get prefix => symbol.length > 1 && !symbol.contains('\$') ? '$symbol ' : symbol;
}

const currencies = [
  Currency('NPR', 'Rs', 'Nepali rupee', indian: true),
  Currency('INR', '₹', 'Indian rupee', indian: true),
  Currency('USD', '\$', 'US dollar'),
  Currency('EUR', '€', 'Euro'),
  Currency('GBP', '£', 'British pound'),
  Currency('AUD', 'A\$', 'Australian dollar'),
  Currency('CAD', 'C\$', 'Canadian dollar'),
  Currency('NZD', 'NZ\$', 'New Zealand dollar'),
  Currency('JPY', '¥', 'Japanese yen'),
  Currency('CNY', '¥', 'Chinese yuan'),
  Currency('KRW', '₩', 'South Korean won'),
  Currency('HKD', 'HK\$', 'Hong Kong dollar'),
  Currency('SGD', 'S\$', 'Singapore dollar'),
  Currency('MYR', 'RM', 'Malaysian ringgit'),
  Currency('THB', '฿', 'Thai baht'),
  Currency('IDR', 'Rp', 'Indonesian rupiah'),
  Currency('PHP', '₱', 'Philippine peso'),
  Currency('BDT', '৳', 'Bangladeshi taka', indian: true),
  Currency('PKR', 'Rs', 'Pakistani rupee', indian: true),
  Currency('LKR', 'Rs', 'Sri Lankan rupee', indian: true),
  Currency('AED', 'AED', 'UAE dirham'),
  Currency('SAR', 'SAR', 'Saudi riyal'),
  Currency('QAR', 'QAR', 'Qatari riyal'),
  Currency('KWD', 'KWD', 'Kuwaiti dinar'),
  Currency('CHF', 'CHF', 'Swiss franc'),
  Currency('ZAR', 'R', 'South African rand'),
  Currency('NGN', '₦', 'Nigerian naira'),
  Currency('KES', 'KSh', 'Kenyan shilling'),
  Currency('BRL', 'R\$', 'Brazilian real'),
  Currency('MXN', 'MX\$', 'Mexican peso'),
];

Currency currencyOf(String code) => currencies.firstWhere((c) => c.code == code, orElse: () => currencies.first);

/// best guess from the phone's region, so most people never touch the picker
String guessCurrency() {
  const byCountry = {
    'NP': 'NPR',
    'IN': 'INR',
    'US': 'USD',
    'GB': 'GBP',
    'AU': 'AUD',
    'CA': 'CAD',
    'NZ': 'NZD',
    'JP': 'JPY',
    'CN': 'CNY',
    'KR': 'KRW',
    'HK': 'HKD',
    'SG': 'SGD',
    'MY': 'MYR',
    'TH': 'THB',
    'ID': 'IDR',
    'PH': 'PHP',
    'BD': 'BDT',
    'PK': 'PKR',
    'LK': 'LKR',
    'AE': 'AED',
    'SA': 'SAR',
    'QA': 'QAR',
    'KW': 'KWD',
    'CH': 'CHF',
    'ZA': 'ZAR',
    'NG': 'NGN',
    'KE': 'KES',
    'BR': 'BRL',
    'MX': 'MXN',
    'DE': 'EUR',
    'FR': 'EUR',
    'IT': 'EUR',
    'ES': 'EUR',
    'NL': 'EUR',
    'IE': 'EUR',
    'PT': 'EUR',
    'AT': 'EUR',
    'BE': 'EUR',
    'FI': 'EUR',
    'GR': 'EUR',
  };
  return byCountry[PlatformDispatcher.instance.locale.countryCode] ?? 'USD';
}

final _indian = [NumberFormat('#,##,##0', 'en_IN'), NumberFormat('#,##,##0.00', 'en_IN')];
final _western = [NumberFormat('#,##0', 'en_US'), NumberFormat('#,##0.00', 'en_US')];

/// Amounts are stored as whole cents so sums never drift.
/// money(123450, cur) -> "Rs 1,234.50", money(-5000, cur) -> "−Rs 50"
String money(int cents, Currency cur, {bool sign = false}) {
  final f = (cur.indian ? _indian : _western)[cents % 100 == 0 ? 0 : 1];
  final digits = f.format(cents.abs() / 100);
  final mark = cents < 0 ? '−' : (sign && cents > 0 ? '+' : '');
  return '$mark${cur.prefix}$digits';
}

/// the keypad's half-typed amount, grouped like everywhere else: "125000." -> "Rs 1,25,000."
String typedMoney(String typed, Currency cur) {
  final dot = typed.indexOf('.');
  final whole = int.tryParse(dot < 0 ? typed : typed.substring(0, dot)) ?? 0;
  return '${cur.prefix}${(cur.indian ? _indian : _western)[0].format(whole)}${dot < 0 ? '' : typed.substring(dot)}';
}

/// "1,234.50" or "1234.5" -> 123450. Returns null for anything that isn't a positive amount.
int? parseCents(String text) {
  final clean = text.replaceAll(RegExp(r'[,\s]'), '');
  if (!RegExp(r'^\d{0,12}(\.\d{0,2})?$').hasMatch(clean) || clean.isEmpty || clean == '.') {
    return null;
  }
  final parts = clean.split('.');
  final whole = int.parse(parts[0].isEmpty ? '0' : parts[0]);
  final frac = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;
  final cents = whole * 100 + frac;
  return cents > 0 ? cents : null;
}

/// plain text for an amount field, no grouping: 123450 -> "1234.5"
String centsToInput(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = abs ~/ 100, frac = abs % 100;
  if (frac == 0) return '$sign$whole';
  return '$sign$whole.${frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '')}';
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// "Today", "Yesterday", "Mon, 22 Sep", or "22 Sep 2025" for other years
String dayLabel(DateTime d) {
  final today = dayOf(DateTime.now());
  final o = dayOf(d);
  // UTC dates so a DST transition day can't shift the diff by an hour
  final diff = DateTime.utc(today.year, today.month, today.day).difference(DateTime.utc(o.year, o.month, o.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff == -1) return 'Tomorrow';
  if (d.year == today.year) return DateFormat('EEE, d MMM').format(d);
  return DateFormat('d MMM y').format(d);
}

String monthLabel(DateTime m) => DateFormat(m.year == DateTime.now().year ? 'MMMM' : 'MMMM y').format(m);

String timeAgo(DateTime t) {
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60} min ago';
  if (s < 86400) return '${s ~/ 3600} h ago';
  return dayLabel(t);
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
