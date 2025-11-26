import 'package:firebase_remote_config/firebase_remote_config.dart';

class FirebaseRemoteConfigService {
  static final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  static Future<void> initialize() async {
    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );

    // Set default values
    await _remoteConfig.setDefaults({
      'enable_lend_feature': true,
      'max_categories': 50,
      'max_accounts': 20,
      'enable_notifications': false,
      'currency_format': 'USD',
      'app_maintenance_message': '',
      'show_maintenance_banner': false,
    });

    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      // Silently continue with defaults on error
    }
  }

  static bool get enableLendFeature => _remoteConfig.getBool('enable_lend_feature');
  static int get maxCategories => _remoteConfig.getInt('max_categories');
  static int get maxAccounts => _remoteConfig.getInt('max_accounts');
  static bool get enableNotifications => _remoteConfig.getBool('enable_notifications');
  static String get currencyFormat => _remoteConfig.getString('currency_format');
  static String get appMaintenanceMessage => _remoteConfig.getString('app_maintenance_message');
  static bool get showMaintenanceBanner => _remoteConfig.getBool('show_maintenance_banner');

  static Future<void> refresh() async {
    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      // Silently continue on refresh error
    }
  }
}
