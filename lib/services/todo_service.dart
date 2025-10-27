import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo.dart';

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
      final todosJson = json.encode(todos.map((todo) => todo.toJson()).toList());
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
    return await saveTodos(todos);
  }

  // Update a todo
  Future<bool> updateTodo(Todo updatedTodo) async {
    final todos = await getTodos();
    final index = todos.indexWhere((todo) => todo.id == updatedTodo.id);
    
    if (index != -1) {
      todos[index] = updatedTodo;
      return await saveTodos(todos);
    }
    return false;
  }

  // Delete a todo
  Future<bool> deleteTodo(String id) async {
    final todos = await getTodos();
    todos.removeWhere((todo) => todo.id == id);
    return await saveTodos(todos);
  }

  // Clear all completed todos
  Future<bool> clearCompleted() async {
    final todos = await getTodos();
    final activeTodos = todos.where((todo) => !todo.isCompleted).toList();
    return await saveTodos(activeTodos);
  }
}
