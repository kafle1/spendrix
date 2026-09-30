import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'sync.dart' show SyncError;

/// Opens Google in the system browser and waits for it to come back to a
/// one-off server on 127.0.0.1. Returns the reply's query plus 'redirect'.
Future<Map<String, String>> signInInBrowser(Future<void> over, Uri Function(String redirect) consent) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // a cancel or timeout ends the wait below
  unawaited(over.whenComplete(() => server.close(force: true)));
  try {
    final redirect = 'http://127.0.0.1:${server.port}';
    if (!await launchUrl(consent(redirect), mode: LaunchMode.externalApplication)) {
      throw const SyncError("Couldn't open your browser for Google sign-in.");
    }
    await for (final req in server) {
      // the browser also asks for /favicon.ico and such
      if (req.uri.path != '/' || req.uri.queryParameters.isEmpty) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        continue;
      }
      req.response.headers.contentType = ContentType.html;
      req.response.write(
        '<!doctype html><meta charset="utf-8"><title>Spendrix</title>'
        '<p style="font-family:sans-serif;margin:3em;text-align:center">You can close this tab and go back to Spendrix.</p>',
      );
      await req.response.close();
      return {...req.uri.queryParameters, 'redirect': redirect};
    }
    throw const SyncError("Google sign-in didn't go through. Try again.");
  } finally {
    await server.close(force: true);
  }
}
