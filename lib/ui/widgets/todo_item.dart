import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/todo.dart';

class TodoItem extends StatelessWidget {
  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const TodoItem({
    super.key,
    required this.todo,
    required this.onToggle,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: todo.isOverdue 
            ? const BorderSide(color: Colors.red, width: 2)
            : todo.isDueSoon
                ? const BorderSide(color: Colors.orange, width: 1)
                : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Checkbox
              Checkbox(
                value: todo.isCompleted,
                onChanged: (_) => onToggle(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                activeColor: todo.isOverdue ? Colors.red : Colors.blue,
              ),
              const SizedBox(width: 12),
              
              // Todo content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: todo.isCompleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        color: todo.isCompleted
                            ? Colors.grey
                            : Colors.black87,
                      ),
                    ),
                    if (todo.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        todo.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: todo.isCompleted
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          decoration: todo.isCompleted
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _PriorityIndicator(priority: todo.priority),
                        const SizedBox(width: 8),
                        if (todo.isOverdue) ...[
                          _StatusIndicator(
                            text: 'OVERDUE',
                            color: Colors.red,
                            icon: Icons.warning,
                          ),
                          const SizedBox(width: 8),
                        ] else if (todo.isDueSoon) ...[
                          _StatusIndicator(
                            text: 'DUE SOON',
                            color: Colors.orange,
                            icon: Icons.schedule,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          DateFormat('MMM dd, yyyy - hh:mm a').format(todo.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: todo.isOverdue 
                                ? Colors.red.shade600
                                : todo.isDueSoon
                                    ? Colors.orange.shade600
                                    : Colors.grey.shade500,
                            fontWeight: todo.isOverdue ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityIndicator extends StatelessWidget {
  final Priority priority;

  const _PriorityIndicator({required this.priority});

  Color get _priorityColor {
    switch (priority) {
      case Priority.low:
        return Colors.green;
      case Priority.medium:
        return Colors.orange;
      case Priority.high:
        return Colors.red;
    }
  }

  String get _priorityLabel {
    switch (priority) {
      case Priority.low:
        return 'Low';
      case Priority.medium:
        return 'Medium';
      case Priority.high:
        return 'High';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _priorityColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _priorityColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        _priorityLabel,
        style: TextStyle(
          color: _priorityColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _StatusIndicator({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
