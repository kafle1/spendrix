import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const _projectId = 'spendrix-68b84';
  static const _messagingSenderId = '540267392506';
  static const _storageBucket = 'spendrix-68b84.firebasestorage.app';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return desktop;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyAFSx0ERt6rT36-5Qd8aMw_qEnHRrRoX6U',
    appId: '1:540267392506:android:c614486d14d288c1844843',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyCTqf4v0RtNvx2rLeQ2VK1mH-S8sqywDcA',
    appId: '1:540267392506:ios:088fca197fdc9a94844843',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
    iosBundleId: 'com.spendrix',
  );

  static const macos = FirebaseOptions(
    apiKey: 'AIzaSyCTqf4v0RtNvx2rLeQ2VK1mH-S8sqywDcA',
    appId: '1:540267392506:ios:088fca197fdc9a94844843',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
    iosBundleId: 'com.spendrix',
  );

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyAFSx0ERt6rT36-5Qd8aMw_qEnHRrRoX6U',
    appId: '1:540267392506:android:c614486d14d288c1844843',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
    authDomain: 'spendrix-68b84.firebaseapp.com',
  );

  static const desktop = FirebaseOptions(
    apiKey: 'AIzaSyAFSx0ERt6rT36-5Qd8aMw_qEnHRrRoX6U',
    appId: '1:540267392506:android:c614486d14d288c1844843',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
  );
}
