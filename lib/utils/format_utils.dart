import 'package:intl/intl.dart';
import '../services/settings_service.dart';

class FormatUtils {
  static String formatCurrency(double amount) {
    final currency = SettingsService.currentCurrency;
    final formatted = NumberFormat('#,##,##0.00').format(amount);
    return '${currency.symbol} $formatted';
  }

  static String formatCurrencyCompact(double amount) {
    final currency = SettingsService.currentCurrency;
    if (amount >= 1000000) {
      return '${currency.symbol} ${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${currency.symbol} ${(amount / 1000).toStringAsFixed(1)}K';
    }
    return formatCurrency(amount);
  }

  static String formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  static String formatDateTime(DateTime dateTime) {
    return DateFormat('MMM dd, yyyy hh:mm a').format(dateTime);
  }

  static String formatTime(DateTime time) {
    return DateFormat('hh:mm a').format(time);
  }

  static String formatShortDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  static String formatMonthYear(DateTime date) {
    return DateFormat('MMMM yyyy').format(date);
  }
}
