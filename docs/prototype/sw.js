// Прототипът трябва да работи в самолетен режим — това е половината от смисъла му.
//
// Но кеш, който винаги печели, значи че нова версия никога не стига до телефона.
// Затова: за самата страница първо се пробва мрежата и се пада към кеша; за
// останалите файлове — обратното. Офлайн работи и в двата случая.
var CACHE = "minava-prototype-7";
var FILES = ["./", "./index.html", "./practices.js", "./facts.js", "./app.webmanifest",
             "./icon-180.png"];

self.addEventListener("install", function (event) {
  event.waitUntil(caches.open(CACHE).then(function (c) { return c.addAll(FILES); }));
  self.skipWaiting();
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (k) { return k !== CACHE; })
                             .map(function (k) { return caches.delete(k); }));
    }).then(function () {
      return self.clients.claim();
    }).then(function () {
      return self.clients.matchAll({ type: "window" });
    }).then(function (clients) {
      // Новата версия е готова, но страницата пред човека е старата. Казваме ѝ и тя
      // решава кога да се презареди — не насред упражнение. Без това съобщение
      // обновяването стига до телефона и стои невидимо до следващото отваряне.
      clients.forEach(function (client) {
        client.postMessage({ type: "minava-updated", cache: CACHE });
      });
    })
  );
});

self.addEventListener("fetch", function (event) {
  var request = event.request;
  var isPage = request.mode === "navigate" ||
               (request.headers.get("accept") || "").indexOf("text/html") !== -1;
  // practices.js е съдържание, не статичен файл: генерира се от clinical/personal/ и
  // се мени. Кеш, който винаги печели, би заключил телефона върху стари упражнения.
  var isContent = request.url.indexOf("practices.js") !== -1 ||
                  request.url.indexOf("facts.js") !== -1;

  if (isPage || isContent) {
    event.respondWith(
      fetch(request).then(function (response) {
        var copy = response.clone();
        caches.open(CACHE).then(function (c) { c.put(request, copy); });
        return response;
      }).catch(function () {
        return caches.match(request).then(function (hit) {
          if (hit) { return hit; }
          // Само страница пада обратно към index.html. Друг файл, върнат като
          // страница, е по-лош от липсващ файл.
          return isPage ? caches.match("./index.html") : Response.error();
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
