import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class FirebaseAnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static final FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: _analytics);

  // Screen tracking
  static Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(
      screenName: screenName,
      screenClass: screenName,
    );
  }

  // Transaction Events
  static Future<void> logTransactionAdded({
    required String type,
    required double amount,
    required String category,
    String? accountName,
  }) async {
    await _analytics.logEvent(
      name: 'transaction_added',
      parameters: {
        'transaction_type': type,
        'amount': amount,
        'category': category,
        'account_name': accountName ?? 'unknown',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  static Future<void> logTransactionEdited({
    required String type,
    required double amount,
  }) async {
    await _analytics.logEvent(
      name: 'transaction_edited',
      parameters: {
        'transaction_type': type,
        'amount': amount,
      },
    );
  }

  static Future<void> logTransactionDeleted({
    required String type,
    required double amount,
  }) async {
    await _analytics.logEvent(
      name: 'transaction_deleted',
      parameters: {
        'transaction_type': type,
        'amount': amount,
      },
    );
  }

  // Category Events
  static Future<void> logCategoryCreated(String categoryName) async {
    await _analytics.logEvent(
      name: 'category_created',
      parameters: {
        'category_name': categoryName,
      },
    );
  }

  static Future<void> logCategoryDeleted(String categoryName) async {
    await _analytics.logEvent(
      name: 'category_deleted',
      parameters: {
        'category_name': categoryName,
      },
    );
  }

  // Account Events
  static Future<void> logAccountCreated(String accountName) async {
    await _analytics.logEvent(
      name: 'account_created',
      parameters: {
        'account_name': accountName,
      },
    );
  }

  static Future<void> logAccountDeleted(String accountName) async {
    await _analytics.logEvent(
      name: 'account_deleted',
      parameters: {
        'account_name': accountName,
      },
    );
  }

  // Lend/Borrow Events
  static Future<void> logLendBorrowAdded({
    required String type,
    required double amount,
    required String personName,
  }) async {
    await _analytics.logEvent(
      name: 'lend_borrow_added',
      parameters: {
        'type': type,
        'amount': amount,
        'person_name': personName,
      },
    );
  }

  static Future<void> logLendBorrowSettled({
    required String type,
    required double amount,
  }) async {
    await _analytics.logEvent(
      name: 'lend_borrow_settled',
      parameters: {
        'type': type,
        'amount': amount,
      },
    );
  }

  // Report Events
  static Future<void> logReportGenerated(String reportType) async {
    await _analytics.logEvent(
      name: 'report_generated',
      parameters: {
        'report_type': reportType,
      },
    );
  }

  static Future<void> logReportExported(String exportFormat) async {
    await _analytics.logEvent(
      name: 'report_exported',
      parameters: {
        'export_format': exportFormat,
      },
    );
  }

  // Settings Events
  static Future<void> logThemeChanged(String themeMode) async {
    await _analytics.logEvent(
      name: 'theme_changed',
      parameters: {
        'theme_mode': themeMode,
      },
    );
  }

  static Future<void> logCurrencyChanged(String currency) async {
    await _analytics.logEvent(
      name: 'currency_changed',
      parameters: {
        'currency': currency,
      },
    );
  }

  static Future<void> logSpendingLimitSet({
    required double amount,
    required String period,
  }) async {
    await _analytics.logEvent(
      name: 'spending_limit_set',
      parameters: {
        'amount': amount,
        'period': period,
      },
    );
  }

  // User Properties
  static Future<void> setUserProperty({
    required String name,
    required String value,
  }) async {
    await _analytics.setUserProperty(name: name, value: value);
  }

  // App Events
  static Future<void> logAppOpen() async {
    await _analytics.logAppOpen();
  }

  static Future<void> logSearch(String searchTerm) async {
    await _analytics.logSearch(
      searchTerm: searchTerm,
    );
  }

  // Error tracking with Crashlytics
  static Future<void> logError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    await FirebaseCrashlytics.instance.recordError(
      exception,
      stackTrace,
      reason: reason,
      fatal: fatal,
    );
  }

  static Future<void> logMessage(String message) async {
    await FirebaseCrashlytics.instance.log(message);
  }

  static Future<void> setUserIdentifier(String userId) async {
    await _analytics.setUserId(id: userId);
    await FirebaseCrashlytics.instance.setUserIdentifier(userId);
  }

  static Future<void> setCustomKey(String key, dynamic value) async {
    await FirebaseCrashlytics.instance.setCustomKey(key, value);
  }
}
