import 'package:web/web.dart' as web;

/// Loads the newest build, which the no-cache headers on /app/ make sure of.
void reloadPage() => web.window.location.reload();

/// The folder the app is served from. baseURI follows the base href, so it is /app/ live whatever the route.
Uri appBase() => Uri.parse(web.document.baseURI);
