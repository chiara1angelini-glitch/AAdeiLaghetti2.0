// Permette all'app di aprirsi anche senza connessione.
// Quando cambi qualcosa nell'app, aumenta il numero di versione qui sotto.
const CACHE = 'laghetti-v5';
const FILES = [
  './',
  './index.html',
  './app.js',
  './style.css',
  './config.js',
  './manifest.webmanifest',
  './logo.png',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  if (new URL(e.request.url).hostname.endsWith('supabase.co')) return; // dati sempre freschi
  e.respondWith(
    fetch(e.request, { cache: 'no-cache' }) // chiede sempre al sito se c'è una versione nuova
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});
