/* Fokus — service worker: offline shell + timer alarm */
const CACHE = 'fokus-v1.0.2';
const ASSETS = [
  './', './index.html', './styles.css', './app.js', './manifest.webmanifest',
  './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png',
  './icons/favicon.svg', './icons/badge.png',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  // Network-first so a redeploy never leaves a stale app behind; cache is the
  // offline safety net.
  e.respondWith((async () => {
    try{
      const res = await fetch(req);
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
      return res;
    } catch {
      const hit = await caches.match(req);
      return hit || caches.match('./index.html');
    }
  })());
});

/* Best-effort in-worker alarm. Chromium also gets a real TimestampTrigger
   from the page; this covers the window where the worker is still alive. */
let alarm = null;
self.addEventListener('message', e => {
  const d = e.data || {};
  if (d.type === 'cancel'){ clearTimeout(alarm); alarm = null; return; }
  if (d.type === 'schedule'){
    clearTimeout(alarm);
    const wait = Math.max(0, d.endsAt - Date.now());
    alarm = setTimeout(() => self.registration.showNotification(d.title, d.options || {}), wait);
  }
});
/* Push utan innehåll: servern knackar bara på. Texten ligger i cachen,
   lagd dit av appen när passet startade. Därför slipper vi kryptera
   nyttolasten — och servern får aldrig veta vad passet handlade om. */
self.addEventListener('push', e => {
  e.waitUntil((async () => {
    let title = 'Passet är klart 🎉', body = '';
    try {
      const c = await caches.open('fokus-alarm');
      const r = await c.match(new URL('__alarm', self.registration.scope).href);
      if (r){ const d = await r.json(); title = d.title || title; body = d.body || body; }
    } catch(err){}
    await self.registration.showNotification(title, {
      body, tag:'fokus-timer', renotify:true, requireInteraction:true,
      icon:'icons/icon-192.png', badge:'icons/badge.png',
      vibrate:[220, 90, 220, 90, 380],
    });
  })());
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type:'window', includeUncontrolled:true }).then(list => {
    for (const c of list){ if ('focus' in c){ c.postMessage({ type:'focus-app' }); return c.focus(); } }
    return self.clients.openWindow('./');
  }));
});
