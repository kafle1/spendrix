class Currency {
  final String code;
  final String symbol;
  final String name;
  final String format; // 'symbol_before' or 'symbol_after'

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    this.format = 'symbol_before',
  });

  static const List<Currency> currencies = [
    Currency(code: 'NPR', symbol: 'Rs', name: 'Nepalese Rupee'),
    Currency(code: 'USD', symbol: '\$', name: 'US Dollar'),
    Currency(code: 'EUR', symbol: '€', name: 'Euro'),
    Currency(code: 'GBP', symbol: '£', name: 'British Pound'),
    Currency(code: 'INR', symbol: '₹', name: 'Indian Rupee'),
    Currency(code: 'JPY', symbol: '¥', name: 'Japanese Yen'),
    Currency(code: 'CNY', symbol: '¥', name: 'Chinese Yuan'),
    Currency(code: 'AUD', symbol: 'A\$', name: 'Australian Dollar'),
    Currency(code: 'CAD', symbol: 'C\$', name: 'Canadian Dollar'),
    Currency(code: 'CHF', symbol: 'CHF', name: 'Swiss Franc'),
    Currency(code: 'AED', symbol: 'د.إ', name: 'UAE Dirham'),
    Currency(code: 'SAR', symbol: 'ر.س', name: 'Saudi Riyal'),
    Currency(code: 'KRW', symbol: '₩', name: 'South Korean Won'),
    Currency(code: 'SGD', symbol: 'S\$', name: 'Singapore Dollar'),
    Currency(code: 'MYR', symbol: 'RM', name: 'Malaysian Ringgit'),
    Currency(code: 'THB', symbol: '฿', name: 'Thai Baht'),
    Currency(code: 'IDR', symbol: 'Rp', name: 'Indonesian Rupiah'),
    Currency(code: 'PHP', symbol: '₱', name: 'Philippine Peso'),
    Currency(code: 'VND', symbol: '₫', name: 'Vietnamese Dong'),
    Currency(code: 'BDT', symbol: '৳', name: 'Bangladeshi Taka'),
    Currency(code: 'PKR', symbol: 'Rs', name: 'Pakistani Rupee'),
    Currency(code: 'LKR', symbol: 'Rs', name: 'Sri Lankan Rupee'),
    Currency(code: 'BRL', symbol: 'R\$', name: 'Brazilian Real'),
    Currency(code: 'MXN', symbol: '\$', name: 'Mexican Peso'),
    Currency(code: 'ZAR', symbol: 'R', name: 'South African Rand'),
    Currency(code: 'RUB', symbol: '₽', name: 'Russian Ruble'),
    Currency(code: 'TRY', symbol: '₺', name: 'Turkish Lira'),
    Currency(code: 'NZD', symbol: 'NZ\$', name: 'New Zealand Dollar'),
    Currency(code: 'HKD', symbol: 'HK\$', name: 'Hong Kong Dollar'),
    Currency(code: 'NGN', symbol: '₦', name: 'Nigerian Naira'),
    Currency(code: 'EGP', symbol: 'E£', name: 'Egyptian Pound'),
    Currency(code: 'KES', symbol: 'KSh', name: 'Kenyan Shilling'),
  ];

  static Currency fromCode(String code) {
    return currencies.firstWhere(
      (c) => c.code == code,
      orElse: () => currencies.first,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'symbol': symbol,
      'name': name,
      'format': format,
    };
  }

  factory Currency.fromMap(Map<String, dynamic> map) {
    return Currency(
      code: map['code'] as String,
      symbol: map['symbol'] as String,
      name: map['name'] as String,
      format: map['format'] as String? ?? 'symbol_before',
    );
  }
}
