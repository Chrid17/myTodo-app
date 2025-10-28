import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo.dart';
import 'notification_service.dart';

class TodoService {
  static const String _todosKey = 'todos';

  // Get all todos from storage
  Future<List<Todo>> getTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todosJson = prefs.getString(_todosKey);

      if (todosJson == null || todosJson.isEmpty) {
        return [];
      }

      final List<dynamic> todosList = json.decode(todosJson);
      return todosList.map((json) => Todo.fromJson(json)).toList();
    } catch (e) {
      print('Error loading todos: $e');
      return [];
    }
  }

  // Save todos to storage
  Future<bool> saveTodos(List<Todo> todos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todosJson = json.encode(
        todos.map((todo) => todo.toJson()).toList(),
      );
      return await prefs.setString(_todosKey, todosJson);
    } catch (e) {
      print('Error saving todos: $e');
      return false;
    }
  }

  // Add a new todo
  Future<bool> addTodo(Todo todo) async {
    final todos = await getTodos();
    todos.add(todo);
    final saved = await saveTodos(todos);
    if (saved) {
      // Schedule notification for the new todo if applicable
      await NotificationService.scheduleNotification(todo);
    }
    return saved;
  }

  // Update a todo
  Future<bool> updateTodo(Todo updatedTodo) async {
    final todos = await getTodos();
    final index = todos.indexWhere((todo) => todo.id == updatedTodo.id);

    if (index != -1) {
      todos[index] = updatedTodo;
      final saved = await saveTodos(todos);
      if (saved) {
        if (updatedTodo.isCompleted) {
          // Cancel notification if the todo was completed
          await NotificationService.cancelNotification(updatedTodo.id);
        } else {
          // Reschedule to apply any changed due time
          await NotificationService.rescheduleNotification(updatedTodo);
        }
      }
      return saved;
    }
    return false;
  }

  // Delete a todo
  Future<bool> deleteTodo(String id) async {
    final todos = await getTodos();
    todos.removeWhere((todo) => todo.id == id);
    final saved = await saveTodos(todos);
    if (saved) {
      await NotificationService.cancelNotification(id);
    }
    return saved;
  }

  // Clear all completed todos
  Future<bool> clearCompleted() async {
    final todos = await getTodos();
    final activeTodos = todos.where((todo) => !todo.isCompleted).toList();
    final removed = todos.where((todo) => todo.isCompleted).toList();
    final saved = await saveTodos(activeTodos);
    if (saved) {
      // Cancel notifications for removed completed todos
      for (final t in removed) {
        await NotificationService.cancelNotification(t.id);
      }
    }
    return saved;
  }
}
