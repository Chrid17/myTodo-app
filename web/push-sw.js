self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// Show incoming Web Push notifications
self.addEventListener('push', (event) => {
  try {
    const data = event.data ? event.data.json() : {};
    const title = data.title || 'Todo Reminder';
    const body = data.body || 'Time to complete your todo!';
    const tag = data.tag || 'todo-reminder';
    const url = data.url || '/';

    const options = {
      body,
      tag,
      data: { url },
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      vibrate: [120, 60, 120],
    };

    event.waitUntil(self.registration.showNotification(title, options));
  } catch (_) {
    // ignore
  }
});

// Focus an existing client or open a new one on click
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    })
  );
});


