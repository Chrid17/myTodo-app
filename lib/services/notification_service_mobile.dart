import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/todo.dart' as model;
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final fln.FlutterLocalNotificationsPlugin _notifications =
      fln.FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // Initialize timezone data
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
    final androidPlugin =
        _notifications
            .resolvePlatformSpecificImplementation<
              fln.AndroidFlutterLocalNotificationsPlugin
            >();

    const fln.AndroidNotificationChannel channel =
        fln.AndroidNotificationChannel(
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
    await _notifications
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await _notifications
        .resolvePlatformSpecificImplementation<
          fln.IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static void _onNotificationTapped(fln.NotificationResponse response) {
    // Handle notification tap - you can navigate to specific todo or app
    print('Notification tapped: ${response.payload}');
  }

  static Future<void> scheduleNotification(model.Todo todo) async {
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
            sound:
                selectedSound == null
                    ? null
                    : fln.RawResourceAndroidNotificationSound(selectedSound),
          );

      final fln.NotificationDetails notificationDetails =
          fln.NotificationDetails(android: androidDetails, iOS: iosDetails);

      // Schedule the main due-time notification
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

      // For high priority, also schedule a 5-minute prior reminder if in the future
      if (todo.priority == model.Priority.high) {
        final DateTime preTime = todo.createdAt.subtract(
          const Duration(minutes: 5),
        );
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
            uiLocalNotificationDateInterpretation:
                fln.UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    }
  }

  static Future<void> cancelNotification(String todoId) async {
    final int notificationId = todoId.hashCode;
    final int preId = '${todoId}_pre'.hashCode;
    await _notifications.cancel(notificationId);
    await _notifications.cancel(preId);
  }

  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  static Future<void> rescheduleNotification(model.Todo todo) async {
    // Cancel existing notification and schedule new one
    await cancelNotification(todo.id);
    await scheduleNotification(todo);
  }

  // Show a small immediate notification to test sound on mobile platforms
  static Future<void> playTestSound() async {
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
            sound:
                selectedSound == null
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
      print('playTestSound failed: $e');
    }
  }

  // Mobile: assume system notification sound is available (no asset check required)
  static Future<bool> audioAssetExists() async {
    return true;
  }

  // Resolve preferred sound name stored in SharedPreferences.
  // Returns null to use the system default sound.
  static Future<String?> _resolveSelectedSound() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('selected_sound');
    if (name == null || name == 'default') return null;
    // On Android, this should match a res/raw/<name> resource (without extension).
    // On iOS, a <name>.wav must be bundled.
    return name;
  }
}
