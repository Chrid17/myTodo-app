import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/todo.dart';
import 'notification_service.dart';
import 'supabase_client.dart';
import 'todo_service.dart' as local_cache;

class SupabaseTodoService {
  static const String table = 'todos';

  SupabaseClient get _db => AppSupabase.client;

  RealtimeChannel? _channel; // no longer used with table stream

  // Map DB row -> Todo
  Todo _fromRow(Map<String, dynamic> row) {
    return Todo(
      id: (row['id'] ?? '').toString(),
      title: row['title'] ?? '',
      description: row['description'] ?? '',
      isCompleted: (row['is_completed'] as bool?) ?? false,
      createdAt: DateTime.parse(row['due_at'] as String),
      priority: _priorityFromText(row['priority'] as String?),
    );
  }

  Map<String, dynamic> _toRow(Todo t, String userId) {
    return {
      'id': t.id, // optional; if null/empty, server will generate
      'user_id': userId,
      'title': t.title,
      'description': t.description,
      'is_completed': t.isCompleted,
      'due_at': t.createdAt.toIso8601String(),
      'priority': t.priority.name,
    };
  }

  Priority _priorityFromText(String? v) {
    switch (v) {
      case 'low':
        return Priority.low;
      case 'high':
        return Priority.high;
      case 'medium':
      default:
        return Priority.medium;
    }
  }

  Future<List<Todo>> getTodos() async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final res = await _db
        .from(table)
        .select()
        .order('due_at', ascending: false);

    final todos = (res as List).cast<Map<String, dynamic>>().map(_fromRow).toList();

    // Mirror to local cache to keep notifications working
    await local_cache.TodoService().saveTodos(todos);

    return todos;
  }

  Stream<List<Todo>> subscribeTodos() {
    final user = _db.auth.currentUser;
    if (user == null) {
      return const Stream<List<Todo>>.empty();
    }
    return _db
        .from(table)
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('due_at', ascending: false)
        .map((rows) => rows.map((r) => _fromRow(r)).toList())
        .asyncMap((todos) async {
          // Mirror to local cache to keep notifications working
          await local_cache.TodoService().saveTodos(todos);
          return todos;
        });
  }

  void dispose() {
    _channel?.unsubscribe();
    _channel = null;
  }

  Future<Todo?> addTodo(Todo t) async {
    final user = _db.auth.currentUser;
    if (user == null) return null;

    final data = _toRow(t, user.id);
    // If t.id is empty, let the server generate; in that case omit id
    if ((t.id).isEmpty) data.remove('id');

    final inserted = await _db
        .from(table)
        .insert(data)
        .select()
        .single();

    final todo = _fromRow(inserted);

    // schedule notification as before
    await NotificationService.scheduleNotification(todo);

    // Update cache
    final todos = await getTodos();
    await local_cache.TodoService().saveTodos(todos);

    return todo;
  }

  Future<bool> updateTodo(Todo t) async {
    final user = _db.auth.currentUser;
    if (user == null) return false;

    await _db
        .from(table)
        .update({
          'title': t.title,
          'description': t.description,
          'is_completed': t.isCompleted,
          'priority': t.priority.name,
          'due_at': t.createdAt.toIso8601String(),
        })
        .eq('id', t.id)
        .eq('user_id', user.id);

    if (t.isCompleted) {
      await NotificationService.cancelNotification(t.id);
    } else {
      await NotificationService.rescheduleNotification(t);
    }

    final todos = await getTodos();
    await local_cache.TodoService().saveTodos(todos);

    return true;
  }

  Future<bool> deleteTodo(String id) async {
    final user = _db.auth.currentUser;
    if (user == null) return false;

    await _db.from(table).delete().eq('id', id).eq('user_id', user.id);

    await NotificationService.cancelNotification(id);

    final todos = await getTodos();
    await local_cache.TodoService().saveTodos(todos);

    return true;
  }
}
