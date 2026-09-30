import 'dart:async';

import 'package:web/web.dart' as web;

import 'sync.dart' show SyncError;

const _slot = 'spendrix-google';

/// Opens Google in a popup that returns to web/auth.html, which drops the
/// reply in localStorage. Google's script never loads next to the sync key.
/// Returns the reply's fragment plus 'redirect'.
Future<Map<String, String>> signInInBrowser(Future<void> over, Uri Function(String redirect) consent) {
  final store = web.window.localStorage;
  store.removeItem(_slot);
  // baseURI follows <base href>, so this is /app/auth.html live and /auth.html on localhost
  final redirect = Uri.parse(web.document.baseURI).resolve('auth.html').toString();
  // no await before this line, or the browser treats the popup as unasked for and blocks it
  final popup = web.window.open(consent(redirect).toString(), 'spendrix-google', 'popup,width=500,height=650');
  if (popup == null) {
    return Future.error(
      const SyncError('Your browser blocked the Google window. Allow pop-ups for this site, then try again.'),
    );
  }
  final done = Completer<Map<String, String>>();
  void check() {
    final reply = store.getItem(_slot);
    if (reply == null || done.isCompleted) return;
    store.removeItem(_slot);
    done.complete({...Uri.splitQueryString(reply), 'redirect': redirect});
  }

  final sub = web.EventStreamProviders.storageEvent.forTarget(web.window).listen((_) => check());
  // some browsers skip the storage event for a popup, so look now and then too
  final poll = Timer.periodic(const Duration(seconds: 1), (_) => check());
  unawaited(
    over.whenComplete(() {
      sub.cancel();
      poll.cancel();
      store.removeItem(_slot);
      try {
        popup.close();
      } catch (_) {}
    }),
  );
  return done.future;
}
