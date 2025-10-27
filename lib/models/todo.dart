enum Priority { low, medium, high }

class Todo {
  final String id;
  final String title;
  final String description;
  final bool isCompleted;
  final DateTime createdAt;
  final Priority priority;

  Todo({
    required this.id,
    required this.title,
    this.description = '',
    this.isCompleted = false,
    required this.createdAt,
    this.priority = Priority.medium,
  });

  // Create a copy with modified fields
  Todo copyWith({
    String? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
    Priority? priority,
  }) {
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      priority: priority ?? this.priority,
    );
  }

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'createdAt': createdAt.toIso8601String(),
      'priority': priority.name,
    };
  }

  // Create from JSON
  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'],
      title: json['title'],
      description: json['description'] ?? '',
      isCompleted: json['isCompleted'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      priority: Priority.values.firstWhere(
        (p) => p.name == json['priority'],
        orElse: () => Priority.medium,
      ),
    );
  }

  // Check if todo is overdue
  bool get isOverdue {
    return !isCompleted && createdAt.isBefore(DateTime.now());
  }

  // Get todo status
  String get status {
    if (isCompleted) return 'Completed';
    if (isOverdue) return 'Overdue';
    return 'Pending';
  }

  // Get time until due (or overdue time)
  Duration get timeUntilDue {
    return createdAt.difference(DateTime.now());
  }

  // Check if todo is due soon (within next hour)
  bool get isDueSoon {
    if (isCompleted || isOverdue) return false;
    final timeUntilDue = this.timeUntilDue;
    return timeUntilDue.isNegative == false && timeUntilDue.inMinutes <= 60;
  }
}
