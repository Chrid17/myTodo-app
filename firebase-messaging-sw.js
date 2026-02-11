// Firebase Messaging Service Worker for web push notifications.
// IMPORTANT: Replace the firebaseConfig below with your actual Firebase project config.
// You get these values from Firebase Console > Project Settings > General > Your apps > Web app

importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDuI5aGi9RlNYlyB1-aMuBXuGsX5kCIAQc',
  authDomain: 'mytodo-app-ce7c2.firebaseapp.com',
  projectId: 'mytodo-app-ce7c2',
  storageBucket: 'mytodo-app-ce7c2.firebasestorage.app',
  messagingSenderId: '559869313503',
  appId: '1:559869313503:android:e5701144e0f70db5a9446a',
});

// Retrieve Firebase Messaging instance to handle background messages
const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Background message received:', payload);

  const title = payload.notification?.title || payload.data?.title || 'Todo Reminder';
  const body = payload.notification?.body || payload.data?.body || 'You have a reminder!';
  const tag = payload.data?.todo_id || 'todo-reminder-' + Date.now();

  const notificationOptions = {
    body: body,
    tag: tag,
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    vibrate: [200, 100, 200, 100, 200],
    data: payload.data || {},
    requireInteraction: true,
    actions: [
      { action: 'view', title: 'View Tasks' },
      { action: 'dismiss', title: 'Dismiss' }
    ]
  };

  return self.registration.showNotification(title, notificationOptions);
});

// Handle notification click
self.addEventListener('notificationclick', (event) => {
  console.log('[firebase-messaging-sw.js] Notification clicked');
  event.notification.close();

  if (event.action === 'dismiss') return;

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow('/');
      }
    })
  );
});
