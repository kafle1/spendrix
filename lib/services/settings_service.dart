import 'package:shared_preferences/shared_preferences.dart';
import '../models/currency.dart';
import '../models/app_settings.dart';

class SettingsService {
  static const String _currencyKey = 'selected_currency';
  static const String _appModeKey = 'app_mode';

  static Currency _currentCurrency = Currency.currencies.first;
  static AppMode _currentAppMode = AppMode.both;

  static Currency get currentCurrency => _currentCurrency;
  static AppMode get currentAppMode => _currentAppMode;

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    final currencyCode = prefs.getString(_currencyKey);
    if (currencyCode != null) {
      _currentCurrency = Currency.fromCode(currencyCode);
    }

    final appModeStr = prefs.getString(_appModeKey);
    if (appModeStr != null) {
      _currentAppMode = AppModeExtension.fromString(appModeStr);
    }
  }

  static Future<void> setCurrency(Currency currency) async {
    _currentCurrency = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currencyKey, currency.code);
  }

  static Future<void> setAppMode(AppMode mode) async {
    _currentAppMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appModeKey, mode.name);
  }

  static bool get hasExpenseTracking => _currentAppMode.hasExpenseTracking;
  static bool get hasLoanTracking => _currentAppMode.hasLoanTracking;
}
