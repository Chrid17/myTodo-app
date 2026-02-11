import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'supabase_client.dart';

/// Top-level background message handler (MUST be a top-level function).
/// Called when the app is in the background or terminated and a push arrives.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM: Background message received: ${message.messageId}');
  debugPrint('FCM: Title: ${message.notification?.title}');
  debugPrint('FCM: Body: ${message.notification?.body}');
  // The system will auto-show the notification on Android/iOS when it
  // contains a `notification` payload. For data-only messages you would
  // show a local notification here.
}

/// Firebase Cloud Messaging service for true cross-platform push notifications.
/// Works on Android, iOS, Web, and macOS when Firebase is configured.
class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static String? _currentToken;
  static bool _initialized = false;

  /// Whether FCM was successfully initialized
  static bool get isInitialized => _initialized;

  /// The current FCM device token (null if not initialized)
  static String? get currentToken => _currentToken;

  /// Initialize FCM: request permissions, get token, listen for messages.
  /// Call this AFTER Firebase.initializeApp() succeeds.
  static Future<void> initialize() async {
    try {
      // Register the background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Request notification permissions (especially important on iOS)
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('FCM: Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM: Notification permission denied by user');
        return;
      }

      // Get the FCM device token
      _currentToken = await _messaging.getToken();
      debugPrint('FCM: Device token: $_currentToken');

      if (_currentToken != null) {
        // Store token in Supabase for server-side push
        await _saveTokenToSupabase(_currentToken!);
      }

      // Listen for token refresh (token can change over time)
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM: Token refreshed: $newToken');
        final oldToken = _currentToken;
        _currentToken = newToken;
        await _saveTokenToSupabase(newToken, oldToken: oldToken);
      });

      // Handle foreground messages (app is open)
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle when user taps a notification that opened the app
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Check if the app was opened from a terminated state via notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      // On iOS, set foreground notification presentation options
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _initialized = true;
      debugPrint('FCM: Initialization complete');
    } catch (e, stack) {
      debugPrint('FCM: Initialization failed: $e');
      debugPrint('FCM: Stack: $stack');
    }
  }

  /// Save the FCM token to Supabase so the edge function can send pushes
  static Future<void> _saveTokenToSupabase(
    String token, {
    String? oldToken,
  }) async {
    try {
      final db = AppSupabase.client;
      final user = db.auth.currentUser;

      // Determine platform
      String platform = 'unknown';
      if (kIsWeb) {
        platform = 'web';
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            platform = 'android';
            break;
          case TargetPlatform.iOS:
            platform = 'ios';
            break;
          case TargetPlatform.macOS:
            platform = 'macos';
            break;
          case TargetPlatform.windows:
            platform = 'windows';
            break;
          case TargetPlatform.linux:
            platform = 'linux';
            break;
          default:
            platform = 'unknown';
        }
      }

      // Delete old token if it changed
      if (oldToken != null && oldToken != token) {
        await db.from('device_tokens').delete().eq('token', oldToken);
      }

      // Upsert the new token
      await db.from('device_tokens').upsert({
        'token': token,
        'user_id': user?.id,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');

      debugPrint('FCM: Token saved to Supabase (platform: $platform)');
    } catch (e) {
      debugPrint('FCM: Failed to save token to Supabase: $e');
    }
  }

  /// Handle a message received while the app is in the foreground.
  /// On Android, FCM does NOT auto-show notification when app is in foreground,
  /// so we show a local notification manually.
  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM: Foreground message: ${message.notification?.title}');

    final notification = message.notification;
    if (notification == null) return;

    // Show local notification so user sees it even when app is open
    _showLocalNotification(
      title: notification.title ?? 'Todo Reminder',
      body: notification.body ?? 'You have a reminder!',
      payload: message.data['todo_id'],
    );
  }

  /// Handle when user taps a notification that opened the app
  static void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('FCM: App opened from notification: ${message.data}');
    // You could navigate to a specific todo here using message.data['todo_id']
  }

  /// Show a local notification (for foreground FCM messages)
  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final flnPlugin = FlutterLocalNotificationsPlugin();

      const androidDetails = AndroidNotificationDetails(
        'todo_reminders',
        'Todo Reminders',
        channelDescription: 'Notifications for todo reminders',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await flnPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('FCM: Failed to show local notification: $e');
    }
  }

  /// Remove the device token from Supabase (e.g., on logout)
  static Future<void> removeToken() async {
    try {
      if (_currentToken != null) {
        final db = AppSupabase.client;
        await db.from('device_tokens').delete().eq('token', _currentToken!);
        debugPrint('FCM: Token removed from Supabase');
      }
      await _messaging.deleteToken();
      _currentToken = null;
      _initialized = false;
    } catch (e) {
      debugPrint('FCM: Failed to remove token: $e');
    }
  }

  /// Subscribe to a topic (useful for broadcast notifications)
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('FCM: Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('FCM: Failed to subscribe to topic $topic: $e');
    }
  }
}
