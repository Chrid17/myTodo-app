import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/todo.dart' as model;
import 'package:shared_preferences/shared_preferences.dart';

// Import local_notifier for desktop platforms only.
// On mobile this import resolves but native symbols are never invoked
// because every call site is gated behind _isDesktop.
import 'package:local_notifier/local_notifier.dart';

/// Universal NotificationService
/// - Android/iOS: fully functional using flutter_local_notifications
///   with zonedSchedule (works even when app is closed/killed)
/// - Windows/Linux/macOS: uses local_notifier + in-app callbacks
class NotificationService {
  static final fln.FlutterLocalNotificationsPlugin _notifications =
      fln.FlutterLocalNotificationsPlugin();

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;
  static bool get _isWindows => Platform.isWindows;
  static bool get _isMacOS => Platform.isMacOS;
  static bool get _isLinux => Platform.isLinux;
  static bool get _isDesktop => _isWindows || _isMacOS || _isLinux;

  static final Map<String, Timer> _winTimers = {}; // id -> timer

  // In-app notification callback for showing alerts when app is open
  static void Function(String title, String body)? _inAppNotifier;

  static Future<void> initialize() async {
    if (_isDesktop) {
      // Desktop: local_notifier does not require explicit initialization
      // on most versions. Proceed and show notifications directly.
      return;
    }

    if (!_isMobile) {
      // No-op for unsupported platforms
      return;
    }

    // ── Mobile (Android / iOS) ──────────────────────────────────────────

    // Initialize timezone data (required for zonedSchedule)
    tz.initializeTimeZones();

    // Android initialization settings
    const fln.AndroidInitializationSettings androidSettings =
        fln.AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const fln.DarwinInitializationSettings iosSettings =
        fln.DarwinInitializationSettings(
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
        .resolvePlatformSpecificImplementation<
            fln.AndroidFlutterLocalNotificationsPlugin>();

    const fln.AndroidNotificationChannel channel =
        fln.AndroidNotificationChannel(
      'todo_reminders', // id
      'Todo Reminders', // title
      description: 'Notifications for todo reminders',
      importance: fln.Importance.high,
      playSound: true,
    );

    await androidPlugin?.createNotificationChannel(channel);

    // Request permissions on both Android and iOS
    await _requestPermissions();

    debugPrint('NotificationService: Mobile initialization complete');
  }

  static Future<void> _requestPermissions() async {
    if (!_isMobile) return;

    // Android 13+ (API 33) requires runtime notification permission
    final androidGranted = await _notifications
        .resolvePlatformSpecificImplementation<
            fln.AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    debugPrint('NotificationService: Android permission granted: $androidGranted');

    // Request exact alarm permission on Android 12+ (API 31)
    // This is critical for scheduled notifications to fire when app is closed
    final exactAlarmGranted = await _notifications
        .resolvePlatformSpecificImplementation<
            fln.AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
    debugPrint('NotificationService: Exact alarm permission: $exactAlarmGranted');

    // iOS permissions
    final iosGranted = await _notifications
        .resolvePlatformSpecificImplementation<
            fln.IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    debugPrint('NotificationService: iOS permission granted: $iosGranted');
  }

  static void _onNotificationTapped(fln.NotificationResponse response) {
    debugPrint('NotificationService: Notification tapped: ${response.payload}');
    // Handle notification tap - you can navigate to specific todo or app
  }

  static Future<void> scheduleNotification(model.Todo todo) async {
    // ── Desktop path ──────────────────────────────────────────────────
    if (_isDesktop) {
      _scheduleDesktopNotification(todo);
      return;
    }

    if (!_isMobile) return;

    // ── Mobile path (Android / iOS) ───────────────────────────────────
    // Only schedule if the todo is in the future and not completed
    if (!todo.isCompleted && todo.createdAt.isAfter(DateTime.now())) {
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

      final fln.DarwinNotificationDetails iosDetails =
          fln.DarwinNotificationDetails(
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

      final fln.AndroidNotificationDetails androidDetails =
          fln.AndroidNotificationDetails(
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

      try {
        // Schedule the main due-time notification
        // androidScheduleMode.exactAllowWhileIdle ensures the alarm fires
        // even in Doze mode / when the app is force-stopped
        await _notifications.zonedSchedule(
          mainNotificationId,
          'Todo Reminder: ${todo.title}',
          todo.description.isNotEmpty
              ? todo.description
              : 'Time to complete your todo!',
          tz.TZDateTime.from(todo.createdAt, tz.local),
          notificationDetails,
          payload: todo.id,
          androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              fln.UILocalNotificationDateInterpretation.absoluteTime,
        );
        debugPrint(
            'NotificationService: Scheduled notification for "${todo.title}" at ${todo.createdAt}');

        // Schedule repeat reminders at T+1min, T+2min, T+3min, T+4min, T+5min
        for (int i = 1; i <= 5; i++) {
          final DateTime repeatTime = todo.createdAt.add(Duration(minutes: i));
          if (repeatTime.isAfter(DateTime.now())) {
            final int repeatId = '${todo.id}_repeat_$i'.hashCode;
            await _notifications.zonedSchedule(
              repeatId,
              'Reminder ($i/5): ${todo.title}',
              todo.description.isNotEmpty
                  ? todo.description
                  : 'Don\'t forget this task!',
              tz.TZDateTime.from(repeatTime, tz.local),
              notificationDetails,
              payload: todo.id,
              androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  fln.UILocalNotificationDateInterpretation.absoluteTime,
            );
          }
        }

        // For high priority, also schedule a 5-minute prior reminder
        if (todo.priority == model.Priority.high) {
          final DateTime preTime =
              todo.createdAt.subtract(const Duration(minutes: 5));
          if (preTime.isAfter(DateTime.now())) {
            final int preNotificationId = '${todo.id}_pre'.hashCode;
            await _notifications.zonedSchedule(
              preNotificationId,
              '⚠️ Due soon: ${todo.title}',
              'Starting in 5 minutes',
              tz.TZDateTime.from(preTime, tz.local),
              notificationDetails,
              payload: todo.id,
              androidScheduleMode:
                  fln.AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  fln.UILocalNotificationDateInterpretation.absoluteTime,
            );
            debugPrint(
                'NotificationService: Scheduled 5-min pre-reminder for "${todo.title}"');
          }
        }
      } catch (e, stack) {
        debugPrint('NotificationService: Failed to schedule: $e');
        debugPrint('NotificationService: Stack: $stack');
      }
    }
  }

  // ── Desktop notification scheduling via local_notifier + Timer ─────────
  static void _scheduleDesktopNotification(model.Todo todo) {
    if (!todo.isCompleted) {
      String title = '⏰ Todo Reminder: ${todo.title}';
      String body = todo.description.isNotEmpty
          ? todo.description
          : 'Time to complete your todo!';
      final Duration diff = todo.createdAt.difference(DateTime.now());
      if (!diff.isNegative) {
        _winTimers['${todo.id}_main']?.cancel();
        _winTimers['${todo.id}_main'] = Timer(diff, () async {
          // Show system notification
          try {
            final notification =
                LocalNotification(title: title, body: body);
            await notification.show();
          } catch (_) {}

          // Play system sound
          try {
            await SystemSound.play(SystemSoundType.alert);
          } catch (_) {}

          // Show in-app notification (snackbar/dialog)
          if (_inAppNotifier != null) {
            _inAppNotifier!(title, body);
          }
        });
      }
      // Repeat reminders at T+1, T+2, T+3, T+4, T+5 min
      for (int i = 1; i <= 5; i++) {
        final DateTime repeatTime = todo.createdAt.add(Duration(minutes: i));
        final Duration repeatDiff = repeatTime.difference(DateTime.now());
        if (!repeatDiff.isNegative) {
          _winTimers['${todo.id}_repeat_$i']?.cancel();
          _winTimers['${todo.id}_repeat_$i'] = Timer(repeatDiff, () async {
            final rTitle = 'Reminder ($i/5): ${todo.title}';
            final rBody = todo.description.isNotEmpty ? todo.description : 'Don\'t forget this task!';
            try {
              final notification = LocalNotification(title: rTitle, body: rBody);
              await notification.show();
            } catch (_) {}
            try { await SystemSound.play(SystemSoundType.alert); } catch (_) {}
            if (_inAppNotifier != null) _inAppNotifier!(rTitle, rBody);
          });
        }
      }
      if (todo.priority == model.Priority.high) {
        final DateTime preTime =
            todo.createdAt.subtract(const Duration(minutes: 5));
        final Duration preDiff = preTime.difference(DateTime.now());
        if (!preDiff.isNegative) {
          _winTimers['${todo.id}_pre']?.cancel();
          _winTimers['${todo.id}_pre'] = Timer(preDiff, () async {
            String preTitle = '⚠️ Due soon: ${todo.title}';
            String preBody = 'Starting in 5 minutes';

            try {
              final notification =
                  LocalNotification(title: preTitle, body: preBody);
              await notification.show();
            } catch (_) {}

            try {
              await SystemSound.play(SystemSoundType.alert);
            } catch (_) {}

            if (_inAppNotifier != null) {
              _inAppNotifier!(preTitle, preBody);
            }
          });
        }
      }
    }
  }

  static Future<void> cancelNotification(String todoId) async {
    if (_isDesktop) {
      _winTimers.remove('${todoId}_main')?.cancel();
      _winTimers.remove('${todoId}_pre')?.cancel();
      for (int i = 1; i <= 5; i++) {
        _winTimers.remove('${todoId}_repeat_$i')?.cancel();
      }
      return;
    }
    if (!_isMobile) return;
    await _notifications.cancel(todoId.hashCode);
    await _notifications.cancel('${todoId}_pre'.hashCode);
    for (int i = 1; i <= 5; i++) {
      await _notifications.cancel('${todoId}_repeat_$i'.hashCode);
    }
  }

  static Future<void> cancelAllNotifications() async {
    if (_isDesktop) {
      for (final t in _winTimers.values) {
        t.cancel();
      }
      _winTimers.clear();
      return;
    }
    if (!_isMobile) return;
    await _notifications.cancelAll();
  }

  static Future<void> rescheduleNotification(model.Todo todo) async {
    await cancelNotification(todo.id);
    await scheduleNotification(todo);
  }

  // Show a small immediate notification to test sound on mobile platforms
  static Future<void> playTestSound() async {
    if (_isDesktop) {
      try {
        final notification = LocalNotification(
            title: 'Test Notification',
            body: 'This is a test notification to check sound');
        await notification.show();
      } catch (_) {}
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
      return;
    }
    if (!_isMobile) return;
    try {
      final String? selectedSound = await _resolveSelectedSound();
      final fln.AndroidNotificationDetails androidDetails =
          fln.AndroidNotificationDetails(
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

      final fln.DarwinNotificationDetails iosDetails =
          fln.DarwinNotificationDetails(
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
      debugPrint('NotificationService: playTestSound failed: $e');
    }
  }

  // Assume system notification sound on mobile when not customized
  static Future<bool> audioAssetExists() async {
    if (_isDesktop) return true;
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

  // Register a callback for in-app notifications (shows snackbar/dialog when task is due)
  static void registerInAppNotifier(
      void Function(String title, String body) fn) {
    _inAppNotifier = fn;
  }

  /// Get the count of currently pending (scheduled) notifications.
  /// Useful to verify notifications are actually registered with the OS.
  static Future<int> getPendingNotificationCount() async {
    if (!_isMobile) return _winTimers.length;
    try {
      final pending = await _notifications.pendingNotificationRequests();
      debugPrint(
          'NotificationService: ${pending.length} pending notifications');
      return pending.length;
    } catch (e) {
      debugPrint('NotificationService: Failed to get pending count: $e');
      return 0;
    }
  }
}
