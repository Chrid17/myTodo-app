import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/todo.dart' hide Priority;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // Initialize timezone data
    tz.initializeTimeZones();

    // Android initialization settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Combined initialization settings
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Initialize the plugin
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions
    await _requestPermissions();
  }

  static Future<void> _requestPermissions() async {
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - you can navigate to specific todo or app
    print('Notification tapped: ${response.payload}');
  }

  static Future<void> scheduleNotification(Todo todo) async {
    // Only schedule if the todo is in the future and not completed
    if (todo.createdAt.isAfter(DateTime.now()) && !todo.isCompleted) {
      final int notificationId = todo.id.hashCode;
      
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'todo_reminders',
        'Todo Reminders',
        channelDescription: 'Notifications for todo reminders',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.zonedSchedule(
        notificationId,
        'Todo Reminder: ${todo.title}',
        todo.description.isNotEmpty 
            ? todo.description 
            : 'Time to complete your todo!',
        tz.TZDateTime.from(todo.createdAt, tz.local),
        notificationDetails,
        payload: todo.id,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  static Future<void> cancelNotification(String todoId) async {
    final int notificationId = todoId.hashCode;
    await _notifications.cancel(notificationId);
  }

  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  static Future<void> rescheduleNotification(Todo todo) async {
    // Cancel existing notification and schedule new one
    await cancelNotification(todo.id);
    await scheduleNotification(todo);
  }
}
