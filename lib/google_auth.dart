import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;

import 'google_auth_io.dart' if (dart.library.js_interop) 'google_auth_web.dart' as browser;
import 'sync.dart' show SyncError;

// ---- OAuth clients from our Google Cloud project (the Spendrix Firebase project). An empty id turns Google sign-in off on that platform. ----

/// "Web application" client. Android uses it too, as serverClientId.
const googleWebClientId = '551388193568-aqqfgtf69a5srag9n51019hentni5rp8.apps.googleusercontent.com';

/// "iOS" client for com.spendrix. Its id and reversed id also go in ios/Runner/Info.plist.
const googleIosClientId = '551388193568-qi2goappemdthm2t9cj3kchtgpmjpdll.apps.googleusercontent.com';

/// "Desktop app" client for macOS, Windows and Linux.
const googleDesktopClientId = '551388193568-8chvc56ojkc786rlpmdacj2cpau1p9tj.apps.googleusercontent.com';
// kept out of the public repo so github's leak scan doesn't get it revoked; ci passes it with --dart-define
const googleDesktopSecret = String.fromEnvironment('GOOGLE_DESKTOP_SECRET');

const _drive = 'https://www.googleapis.com/auth/drive.appdata';

/// What a Google sign-in hands back.
class GoogleTokens {
  const GoogleTokens(this.idToken, this.drive, [this.nonce]);

  final String idToken;

  /// the Drive app folder, null when the box was unticked or Drive is off for the account
  final String? drive;

  /// the raw nonce the id token was made for, which Firebase checks
  final String? nonce;
}

const cancelled = SyncError('Google sign-in was cancelled.');
const _failed = SyncError("Google sign-in didn't go through. Try again.");
const _notSetUp = SyncError("Google sign-in isn't set up in this build yet.");

bool get _mobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Signs in with Google and asks for the Drive app folder.
/// On the web the popup opens before the first await, so call it straight from a tap.
Future<GoogleTokens> googleSignIn() {
  if (kIsWeb) return _web();
  return _mobile ? _plugin() : _desktop();
}

Completer<void>? _stop;

/// Stops a sign-in that waits on the browser.
void cancelGoogleSignIn() {
  if (_stop case final c? when !c.isCompleted) c.complete();
}

// a closed tab never answers, so the wait needs a way out. [start] gets a future that ends when the wait does.
Future<T> _wait<T>(Future<T> Function(Future<void> over) start) {
  final stop = _stop = Completer<void>();
  final over = Completer<void>();
  return Future.any([start(over.future), stop.future.then<T>((_) => throw cancelled)])
      .timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw const SyncError('Google sign-in took too long. Try again.'),
      )
      .whenComplete(over.complete);
}

String _random() => base64Url.encode(List.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');

String _sha256(String s, {bool hex = false}) {
  final bytes = const DartSha256().hashSync(utf8.encode(s)).bytes;
  return hex
      ? bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()
      : base64Url.encode(bytes).replaceAll('=', '');
}

Uri _consent(String clientId, String redirect, Map<String, String> extra) =>
    Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirect,
      'scope': 'openid email $_drive',
      'prompt': 'select_account',
      ...extra,
    });

// the consent screen lets people untick Drive, so only trust a token that got it
String? _driveIf(String? token, String? scope) => token != null && (scope ?? '').split(' ').contains(_drive) ? token : null;

Future<GoogleTokens> _web() async {
  if (googleWebClientId.isEmpty) throw _notSetUp;
  final state = _random(), nonce = _random();
  final p = await _wait(
    (over) => browser.signInInBrowser(
      over,
      (redirect) => _consent(googleWebClientId, redirect, {
        'response_type': 'id_token token',
        'state': state,
        'nonce': _sha256(nonce, hex: true),
      }),
    ),
  );
  if (p['state'] != state) throw _failed;
  if (p['error'] != null) throw p['error'] == 'access_denied' ? cancelled : _failed;
  final id = p['id_token'];
  if (id == null) throw _failed;
  return GoogleTokens(id, _driveIf(p['access_token'], p['scope']), nonce);
}

Future<GoogleTokens> _desktop() async {
  if (googleDesktopClientId.isEmpty || googleDesktopSecret.isEmpty) throw _notSetUp;
  final state = _random(), verifier = _random();
  final p = await _wait(
    (over) => browser.signInInBrowser(
      over,
      (redirect) => _consent(googleDesktopClientId, redirect, {
        'response_type': 'code',
        'state': state,
        'code_challenge': _sha256(verifier),
        'code_challenge_method': 'S256',
      }),
    ),
  );
  if (p['state'] != state) throw _failed;
  if (p['error'] != null) throw p['error'] == 'access_denied' ? cancelled : _failed;
  final code = p['code'];
  if (code == null) throw _failed;
  final http.Response res;
  try {
    res = await http
        .post(
          Uri.https('oauth2.googleapis.com', '/token'),
          body: {
            'code': code,
            'client_id': googleDesktopClientId,
            'client_secret': googleDesktopSecret,
            'redirect_uri': p['redirect']!,
            'grant_type': 'authorization_code',
            'code_verifier': verifier,
          },
        )
        .timeout(const Duration(seconds: 30));
  } on Exception {
    throw const SyncError('No internet right now. Everything is saved on this device.');
  }
  try {
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final id = j['id_token'];
    if (res.statusCode != 200 || id is! String) throw _failed;
    return GoogleTokens(id, _driveIf(j['access_token'] as String?, j['scope'] as String?));
  } on FormatException {
    throw _failed;
  } on TypeError {
    throw _failed;
  }
}

Future<void>? _init;

Future<GoogleTokens> _plugin() async {
  final ios = defaultTargetPlatform == TargetPlatform.iOS;
  if (googleWebClientId.isEmpty || (ios && googleIosClientId.isEmpty)) throw _notSetUp;
  final g = GoogleSignInPlatform.instance;
  try {
    await (_init ??= g.init(
      InitParameters(clientId: ios ? googleIosClientId : null, serverClientId: googleWebClientId),
    ).catchError((Object e) {
      _init = null;
      throw e;
    }));
    // forget the last pick, so a person with two Google accounts gets to choose
    await g.signOut(const SignOutParams()).catchError((_) {});
    final r = await g.authenticate(const AuthenticateParameters(scopeHint: [_drive]));
    final id = r.authenticationTokens.idToken;
    if (id == null) throw _failed;
    String? drive;
    try {
      drive = (await g.clientAuthorizationTokensForScopes(
        ClientAuthorizationTokensForScopesParameters(
          request: AuthorizationRequestDetails(
            scopes: const [_drive],
            userId: r.user.id,
            email: r.user.email,
            promptIfUnauthorized: true,
          ),
        ),
      ))?.accessToken;
    } on GoogleSignInException catch (e) {
      // saying no to Drive still signs in, the sync key covers it
      if (e.code != GoogleSignInExceptionCode.canceled) debugPrint('google drive: $e');
    }
    return GoogleTokens(id, drive);
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) throw cancelled;
    debugPrint('google sign-in: $e');
    throw e.code == GoogleSignInExceptionCode.clientConfigurationError ? _notSetUp : _failed;
  } on SyncError {
    rethrow;
  } catch (e) {
    debugPrint('google sign-in: $e');
    throw _failed;
  }
}
