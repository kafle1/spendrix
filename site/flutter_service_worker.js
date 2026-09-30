// the app moved from / to /app/, so this replaces the old root worker, clears its caches and sends tabs to /app/
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // only the old app shell caches: flutter_gemma_models holds the downloaded AI and must stay
    for (const key of await caches.keys()) {
      if (key.startsWith('flutter-app-') || key === 'flutter-temp-cache') await caches.delete(key);
    }
    const tabs = await self.clients.matchAll({ type: 'window' });
    for (const tab of tabs) {
      if (!new URL(tab.url).pathname.startsWith('/app/')) tab.navigate('/app/').catch(() => {});
    }
    await self.registration.unregister();
  })());
});
