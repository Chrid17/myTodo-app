import 'package:intl/intl.dart';

/// Formats a DateTime for display in task cards.
/// Uses relative labels: "Today 3:00 PM", "Tomorrow 9:00 AM", "Yesterday", etc.
String formatTaskDueDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dueDate = DateTime(date.year, date.month, date.day);
  final difference = dueDate.difference(today).inDays;

  final timeStr = DateFormat('h:mm a').format(date);

  if (difference == 0) {
    return 'Today $timeStr';
  } else if (difference == 1) {
    return 'Tomorrow $timeStr';
  } else if (difference == -1) {
    return 'Yesterday $timeStr';
  } else if (difference > 0 && difference <= 7) {
    return '${DateFormat('EEEE').format(date)} $timeStr';
  } else if (difference > -7 && difference < 0) {
    return '${DateFormat('EEE').format(date)} $timeStr';
  } else {
    return DateFormat('MMM d, h:mm a').format(date);
  }
}
