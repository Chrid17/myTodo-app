// Push Notification Service Worker for Todo App
// Handles background push notifications even when the browser tab is closed

const SW_VERSION = '1.0.0';
console.log('[Push SW] Service Worker version:', SW_VERSION);

self.addEventListener('install', (event) => {
  console.log('[Push SW] Installing service worker...');
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  console.log('[Push SW] Activating service worker...');
  event.waitUntil(self.clients.claim());
});

// Handle incoming push notifications
self.addEventListener('push', (event) => {
  console.log('[Push SW] Push notification received');
  
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    console.error('[Push SW] Error parsing push data:', e);
    data = { title: 'Todo Reminder', body: event.data?.text() || 'You have a reminder!' };
  }

  const title = data.title || '⏰ Todo Reminder';
  const body = data.body || 'Time to complete your todo!';
  const tag = data.tag || 'todo-reminder-' + Date.now();
  const url = data.url || '/';

  const options = {
    body: body,
    tag: tag,
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    vibrate: [200, 100, 200, 100, 200],
    data: { url: url },
    requireInteraction: true, // Keep notification visible until user interacts
    actions: [
      { action: 'view', title: 'View Tasks' },
      { action: 'dismiss', title: 'Dismiss' }
    ]
  };

  console.log('[Push SW] Showing notification:', title);
  event.waitUntil(self.registration.showNotification(title, options));
});

// Handle notification click
self.addEventListener('notificationclick', (event) => {
  console.log('[Push SW] Notification clicked:', event.action);
  event.notification.close();

  if (event.action === 'dismiss') {
    return;
  }

  // Get the URL from notification data or use root
  const urlToOpen = (event.notification.data && event.notification.data.url) || '/';
  
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // Try to focus an existing window
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          console.log('[Push SW] Focusing existing window');
          return client.focus();
        }
      }
      // Open a new window if none exists
      if (self.clients.openWindow) {
        console.log('[Push SW] Opening new window');
        return self.clients.openWindow(urlToOpen);
      }
    })
  );
});

// Handle notification close
self.addEventListener('notificationclose', (event) => {
  console.log('[Push SW] Notification closed');
});


