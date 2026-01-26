import 'package:flutter/foundation.dart';
import 'supabase_client.dart';
import '../models/todo.dart';

/// Service for scheduling push notifications via Supabase
/// These notifications work even when the browser/app is closed
class PushNotificationService {
  static const String _table = 'scheduled_notifications';
  
  /// Schedule a push notification for a todo
  /// This stores the notification in Supabase so a backend function can send it
  static Future<void> scheduleNotification(Todo todo) async {
    debugPrint('PushNotificationService: Attempting to schedule for ${todo.title}');
    debugPrint('PushNotificationService: Due at ${todo.createdAt}, isCompleted: ${todo.isCompleted}');
    debugPrint('PushNotificationService: Is future? ${todo.createdAt.isAfter(DateTime.now())}');
    
    // Schedule if the todo is not completed (regardless of time - we'll schedule anyway)
    if (todo.isCompleted) {
      debugPrint('PushNotificationService: Skipping - todo is completed');
      return;
    }
    
    try {
      final db = AppSupabase.client;
      final user = db.auth.currentUser;
      debugPrint('PushNotificationService: User ID: ${user?.id}');
      
      // Delete any existing scheduled notification for this todo
      await db
          .from(_table)
          .delete()
          .eq('todo_id', todo.id);
      debugPrint('PushNotificationService: Deleted old notifications');
      
      // Insert new scheduled notification
      final insertData = {
        'todo_id': todo.id,
        'user_id': user?.id,
        'title': '⏰ Todo Reminder: ${todo.title}',
        'body': todo.description.isNotEmpty 
            ? todo.description 
            : 'Time to complete your todo!',
        'scheduled_at': todo.createdAt.toUtc().toIso8601String(),
      };
      debugPrint('PushNotificationService: Inserting: $insertData');
      
      await db.from(_table).insert(insertData);
      debugPrint('PushNotificationService: SUCCESS - notification scheduled for: ${todo.title}');
      
      // For high priority, also schedule a 5-minute reminder
      if (todo.priority == Priority.high) {
        final preTime = todo.createdAt.subtract(const Duration(minutes: 5));
        if (preTime.isAfter(DateTime.now())) {
          await db.from(_table).insert({
            'todo_id': '${todo.id}_pre',
            'user_id': user?.id,
            'title': '⚠️ Due soon: ${todo.title}',
            'body': 'Starting in 5 minutes',
            'scheduled_at': preTime.toUtc().toIso8601String(),
          });
          debugPrint('PushNotificationService: Pre-notification also scheduled');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('PushNotificationService: FAILED to schedule: $e');
      debugPrint('PushNotificationService: Stack: $stackTrace');
    }
  }
  
  /// Cancel a scheduled push notification
  static Future<void> cancelNotification(String todoId) async {
    try {
      final db = AppSupabase.client;
      
      // Delete both main and pre notifications
      await db
          .from(_table)
          .delete()
          .eq('todo_id', todoId);
      
      await db
          .from(_table)
          .delete()
          .eq('todo_id', '${todoId}_pre');
          
    } catch (e) {
      debugPrint('Failed to cancel push notification: $e');
    }
  }
  
  /// Reschedule a notification (cancel and recreate)
  static Future<void> rescheduleNotification(Todo todo) async {
    await cancelNotification(todo.id);
    await scheduleNotification(todo);
  }
}
