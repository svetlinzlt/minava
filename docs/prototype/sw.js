// Прототипът трябва да работи в самолетен режим — това е половината от смисъла му.
//
// Но кеш, който винаги печели, значи че нова версия никога не стига до телефона.
// Затова: за самата страница първо се пробва мрежата и се пада към кеша; за
// останалите файлове — обратното. Офлайн работи и в двата случая.
var CACHE = "minava-prototype-2";
var FILES = ["./", "./index.html", "./app.webmanifest", "./icon-180.png"];

self.addEventListener("install", function (event) {
  event.waitUntil(caches.open(CACHE).then(function (c) { return c.addAll(FILES); }));
  self.skipWaiting();
});

self.addEventListener("activate", function (event) {
  event.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== CACHE; })
                           .map(function (k) { return caches.delete(k); }));
  }));
  self.clients.claim();
});

self.addEventListener("fetch", function (event) {
  var request = event.request;
  var isPage = request.mode === "navigate" ||
               (request.headers.get("accept") || "").indexOf("text/html") !== -1;

  if (isPage) {
    event.respondWith(
      fetch(request).then(function (response) {
        var copy = response.clone();
        caches.open(CACHE).then(function (c) { c.put(request, copy); });
        return response;
      }).catch(function () {
        return caches.match(request).then(function (hit) {
          return hit || caches.match("./index.html");
        });
      })
    );
    return;
  }

  event.respondWith(
    caches.match(request).then(function (hit) {
      return hit || fetch(request);
    })
  );
});
