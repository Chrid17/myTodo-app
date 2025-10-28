// Placeholder Firebase Messaging service worker.
// You must replace the firebaseConfig with your project's config in your web app
// and initialize firebase in your web/index.html or main.dart.js.

importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

// Initialize the Firebase app in the service worker by passing in your messagingSenderId.
// firebase.initializeApp({
//   apiKey: '<API_KEY>',
//   authDomain: '<PROJECT_ID>.firebaseapp.com',
//   projectId: '<PROJECT_ID>',
//   storageBucket: '<PROJECT_ID>.appspot.com',
//   messagingSenderId: '<SENDER_ID>',
//   appId: '<APP_ID>',
//   measurementId: '<MEASUREMENT_ID>'
//});

// Retrieve an instance of Firebase Messaging so that it can handle background messages.
const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification?.title || 'Background Message Title';
  const notificationOptions = {
    body: payload.notification?.body || 'Background Message body.',
    // You can set an icon here
    // icon: '/icons/icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
