import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:local_notifier/local_notifier.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/todo.dart' as model;
import 'package:shared_preferences/shared_preferences.dart';

/// Universal NotificationService
/// - Android/iOS: fully functional using flutter_local_notifications
/// - Other (Windows/Linux/macOS when unsupported): no-op to avoid crashes
class NotificationService {
  static final fln.FlutterLocalNotificationsPlugin _notifications =
      fln.FlutterLocalNotificationsPlugin();

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;
  static bool get _isWindows => Platform.isWindows;
  static bool get _isMacOS => Platform.isMacOS;
  static bool get _isLinux => Platform.isLinux;
  static bool get _isDesktop => _isWindows || _isMacOS || _isLinux;

  static void Function(String title, String body)? _inAppNotifier; // for Windows
  static final Map<String, Timer> _winTimers = {}; // id -> timer

  static Future<void> initialize() async {
    if (_isDesktop) {
      // Older versions of local_notifier don't require explicit initialization
      // and may not expose LocalNotifier.initialize.
      // Proceed without init and show notifications directly.
      return;
    }
    if (!_isMobile) {
      // No-op for unsupported platforms
      return;
    }

    // Initialize timezone data
    tz.initializeTimeZones();

    // Android initialization settings
    const fln.AndroidInitializationSettings androidSettings =
        fln.AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const fln.DarwinInitializationSettings iosSettings = fln.DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Combined initialization settings
    const fln.InitializationSettings initSettings = fln.InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Initialize the plugin
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create Android notification channel so sound and importance work on Android 8+
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();

    const fln.AndroidNotificationChannel channel = fln.AndroidNotificationChannel(
      'todo_reminders', // id
      'Todo Reminders', // title
      description: 'Notifications for todo reminders',
      importance: fln.Importance.high,
      playSound: true,
    );

    await androidPlugin?.createNotificationChannel(channel);

    // Request permissions
    await _requestPermissions();
  }

  static Future<void> _requestPermissions() async {
    if (!_isMobile) return;

    await _notifications
        .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notifications
        .resolvePlatformSpecificImplementation<fln.IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static void _onNotificationTapped(fln.NotificationResponse response) {
    if (!_isMobile) return;
    // Handle notification tap - you can navigate to specific todo or app
    // ignore: avoid_print
    print('Notification tapped: ${response.payload}');
  }

  static Future<void> scheduleNotification(model.Todo todo) async {
    if (_isDesktop) {
      // schedule native OS toast via local_notifier using a Timer while app runs
      if (!todo.isCompleted) {
        String title = 'Todo Reminder: ${todo.title}';
        String body = todo.description.isNotEmpty ? todo.description : 'Time to complete your todo!';
        final Duration diff = todo.createdAt.difference(DateTime.now());
        if (!diff.isNegative) {
          _winTimers['${todo.id}_main']?.cancel();
          _winTimers['${todo.id}_main'] = Timer(diff, () async {
            try {
              final notification = LocalNotification(title: title, body: body);
              await notification.show();
            } catch (_) {}
            try { await SystemSound.play(SystemSoundType.alert); } catch (_) {}
          });
        }
        if (todo.priority == model.Priority.high) {
          final DateTime preTime = todo.createdAt.subtract(const Duration(minutes: 5));
          final Duration preDiff = preTime.difference(DateTime.now());
          if (!preDiff.isNegative) {
            _winTimers['${todo.id}_pre']?.cancel();
            _winTimers['${todo.id}_pre'] = Timer(preDiff, () async {
              try {
                final notification = LocalNotification(title: 'Due soon: ${todo.title}', body: 'Starting in 5 minutes');
                await notification.show();
              } catch (_) {}
              try { await SystemSound.play(SystemSoundType.alert); } catch (_) {}
            });
          }
        }
      }
      return;
    }

    if (!_isMobile) return;
    // Only schedule if the todo is in the future and not completed
    if (todo.createdAt.isAfter(DateTime.now()) && !todo.isCompleted) {
      final int mainNotificationId = todo.id.hashCode;

      // Map Todo priority to platform-specific urgency
      final fln.Importance androidImportance = switch (todo.priority) {
        model.Priority.low => fln.Importance.low,
        model.Priority.medium => fln.Importance.high,
        model.Priority.high => fln.Importance.max,
      };
      final fln.Priority androidPriority = switch (todo.priority) {
        model.Priority.low => fln.Priority.low,
        model.Priority.medium => fln.Priority.high,
        model.Priority.high => fln.Priority.max,
      };

      // Resolve user-selected sound name (null means use system default)
      final String? selectedSound = await _resolveSelectedSound();

      final fln.DarwinNotificationDetails iosDetails = fln.DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: selectedSound == null ? null : '$selectedSound.wav',
        // Elevate high priority to timeSensitive on iOS 15+
        interruptionLevel: switch (todo.priority) {
          model.Priority.low => fln.InterruptionLevel.passive,
          model.Priority.medium => fln.InterruptionLevel.active,
          model.Priority.high => fln.InterruptionLevel.timeSensitive,
        },
      );

      final fln.AndroidNotificationDetails androidDetails = fln.AndroidNotificationDetails(
        'todo_reminders',
        'Todo Reminders',
        channelDescription: 'Notifications for todo reminders',
        importance: androidImportance,
        priority: androidPriority,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        sound: selectedSound == null
            ? null
            : fln.RawResourceAndroidNotificationSound(selectedSound),
      );

      final fln.NotificationDetails notificationDetails =
          fln.NotificationDetails(android: androidDetails, iOS: iosDetails);

      // Schedule the main due-time notification
      await _notifications.zonedSchedule(
        mainNotificationId,
        'Todo Reminder: ${todo.title}',
        todo.description.isNotEmpty ? todo.description : 'Time to complete your todo!',
        tz.TZDateTime.from(todo.createdAt, tz.local),
        notificationDetails,
        payload: todo.id,
        androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: fln.UILocalNotificationDateInterpretation.absoluteTime,
      );

      // For high priority, also schedule a 5-minute prior reminder if in the future
      if (todo.priority == model.Priority.high) {
        final DateTime preTime = todo.createdAt.subtract(const Duration(minutes: 5));
        if (preTime.isAfter(DateTime.now())) {
          final int preNotificationId = '${todo.id}_pre'.hashCode;
          await _notifications.zonedSchedule(
            preNotificationId,
            'Due soon: ${todo.title}',
            'Starting in 5 minutes',
            tz.TZDateTime.from(preTime, tz.local),
            notificationDetails,
            payload: todo.id,
            androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: fln.UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    }
  }

  static Future<void> cancelNotification(String todoId) async {
    if (_isDesktop) {
      _winTimers.remove('${todoId}_main')?.cancel();
      _winTimers.remove('${todoId}_pre')?.cancel();
      return;
    }
    if (!_isMobile) return;
    final int notificationId = todoId.hashCode;
    final int preId = '${todoId}_pre'.hashCode;
    await _notifications.cancel(notificationId);
    await _notifications.cancel(preId);
  }

  static Future<void> cancelAllNotifications() async {
    if (_isDesktop) {
      for (final t in _winTimers.values) { t.cancel(); }
      _winTimers.clear();
      return;
    }
    if (!_isMobile) return;
    await _notifications.cancelAll();
  }

  static Future<void> rescheduleNotification(model.Todo todo) async {
    if (_isDesktop) {
      await cancelNotification(todo.id);
      await scheduleNotification(todo);
      return;
    }
    if (!_isMobile) return;
    // Cancel existing notification and schedule new one
    await cancelNotification(todo.id);
    await scheduleNotification(todo);
  }

  // Show a small immediate notification to test sound on mobile platforms
  static Future<void> playTestSound() async {
    if (_isDesktop) {
      try {
        final notification = LocalNotification(title: 'Test Notification', body: 'This is a test notification to check sound');
        await notification.show();
      } catch (_) {}
      try { await SystemSound.play(SystemSoundType.alert); } catch (_) {}
      return;
    }
    if (!_isMobile) return;
    try {
      final String? selectedSound = await _resolveSelectedSound();
      final fln.AndroidNotificationDetails androidDetails = fln.AndroidNotificationDetails(
        'todo_reminders',
        'Todo Reminders',
        channelDescription: 'Notifications for todo reminders',
        importance: fln.Importance.high,
        priority: fln.Priority.high,
        playSound: true,
        sound: selectedSound == null
            ? null
            : fln.RawResourceAndroidNotificationSound(selectedSound),
      );

      final fln.DarwinNotificationDetails iosDetails = fln.DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: selectedSound == null ? null : '$selectedSound.wav',
      );

      final fln.NotificationDetails notificationDetails =
          fln.NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        'Test Notification',
        'This is a test notification to check sound',
        notificationDetails,
      );
    } catch (e) {
      // ignore
    }
  }

  // Assume system notification sound on mobile when not customized
  static Future<bool> audioAssetExists() async {
    if (_isWindows) return true;
    if (!_isMobile) return false;
    return true;
  }

  // Resolve preferred sound name stored in SharedPreferences.
  // Returns null to use the system default sound.
  static Future<String?> _resolveSelectedSound() async {
    if (_isDesktop) return null;
    if (!_isMobile) return null;
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('selected_sound');
    if (name == null || name == 'default') return null;
    return name;
  }

  // Register a callback for in-app notifications (no longer used on desktop after using local_notifier)
  static void registerInAppNotifier(void Function(String title, String body) fn) {
    _inAppNotifier = fn;
  }
}
