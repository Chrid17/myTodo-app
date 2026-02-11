// File generated based on flutterfire configure output for project: mytodo-app-ce7c2
// firebase_options.dart

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'run flutterfire configure to fix this.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDuI5aGi9RlNYlyB1-aMuBXuGsX5kCIAQc',
    appId: '1:559869313503:android:e5701144e0f70db5a9446a',
    messagingSenderId: '559869313503',
    projectId: 'mytodo-app-ce7c2',
    storageBucket: 'mytodo-app-ce7c2.firebasestorage.app',
  );

  // Note: Add your iOS app to Firebase Console, then run flutterfire configure
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDuI5aGi9RlNYlyB1-aMuBXuGsX5kCIAQc',
    appId: '1:559869313503:android:e5701144e0f70db5a9446a',
    messagingSenderId: '559869313503',
    projectId: 'mytodo-app-ce7c2',
    storageBucket: 'mytodo-app-ce7c2.firebasestorage.app',
    iosBundleId: 'com.example.myProject',
  );

  // Note: Add your web app to Firebase Console, then run flutterfire configure
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDuI5aGi9RlNYlyB1-aMuBXuGsX5kCIAQc',
    appId: '1:559869313503:android:e5701144e0f70db5a9446a',
    messagingSenderId: '559869313503',
    projectId: 'mytodo-app-ce7c2',
    storageBucket: 'mytodo-app-ce7c2.firebasestorage.app',
    authDomain: 'mytodo-app-ce7c2.firebaseapp.com',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDuI5aGi9RlNYlyB1-aMuBXuGsX5kCIAQc',
    appId: '1:559869313503:android:e5701144e0f70db5a9446a',
    messagingSenderId: '559869313503',
    projectId: 'mytodo-app-ce7c2',
    storageBucket: 'mytodo-app-ce7c2.firebasestorage.app',
    iosBundleId: 'com.example.myProject',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDuI5aGi9RlNYlyB1-aMuBXuGsX5kCIAQc',
    appId: '1:559869313503:android:e5701144e0f70db5a9446a',
    messagingSenderId: '559869313503',
    projectId: 'mytodo-app-ce7c2',
    storageBucket: 'mytodo-app-ce7c2.firebasestorage.app',
  );
}
