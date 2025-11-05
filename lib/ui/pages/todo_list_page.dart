import 'package:flutter/material.dart';
import '../../models/todo.dart';
import '../../services/todo_service.dart';
import '../../services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/todo_item.dart';
import 'add_todo_page.dart';

enum TodoFilter { all, active, completed, overdue }

class TodoListPage extends StatefulWidget {
  const TodoListPage({super.key});

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> {
  final TodoService _todoService = TodoService();
  List<Todo> _todos = [];
  TodoFilter _currentFilter = TodoFilter.all;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadTodos();
    await _maybeShowNotificationPrompt();
  }

  Future<void> _maybeShowNotificationPrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool('notifications_prompt_shown') ?? false;
      if (shown) return;

      final assetExists = await NotificationService.audioAssetExists();

      // Show a dialog prompting the user to enable notifications / test sound
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Enable notifications & sound'),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  const Text(
                    'To hear reminder sounds, allow notifications and tap "Enable & Test".',
                  ),
                  const SizedBox(height: 8),
                  if (!assetExists)
                    const Text(
                      'Note: no audio file found at assets/sounds/notify.mp3. Add a short notify.mp3 file to enable custom sounds.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Maybe later'),
                onPressed: () async {
                  await prefs.setBool('notifications_prompt_shown', true);
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('Enable & Test'),
                onPressed: () async {
                  try {
                    await NotificationService.playTestSound();
                  } catch (e) {
                    // ignore
                  }
                  await prefs.setBool('notifications_prompt_shown', true);
                  await prefs.setBool('notifications_primed', true);
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error showing notification prompt: $e');
    }
  }

  Future<void> _loadTodos() async {
    setState(() => _isLoading = true);
    final todos = await _todoService.getTodos();
    setState(() {
      _todos = todos;
      _isLoading = false;
    });
  }

  List<Todo> get _filteredTodos {
    switch (_currentFilter) {
      case TodoFilter.active:
        return _todos.where((todo) => !todo.isCompleted).toList();
      case TodoFilter.completed:
        return _todos.where((todo) => todo.isCompleted).toList();
      case TodoFilter.overdue:
        return _todos.where((todo) => todo.isOverdue).toList();
      case TodoFilter.all:
        return _todos;
    }
  }

  Future<void> _toggleTodo(Todo todo) async {
    final updatedTodo = todo.copyWith(isCompleted: !todo.isCompleted);
    await _todoService.updateTodo(updatedTodo);
    await _loadTodos();
  }

  Future<void> _deleteTodo(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Todo'),
            content: const Text('Are you sure you want to delete this todo?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _todoService.deleteTodo(id);
      await _loadTodos();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Todo deleted')));
      }
    }
  }

  Future<void> _clearCompleted() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Completed'),
            content: const Text(
              'Are you sure you want to delete all completed todos?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Clear'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _todoService.clearCompleted();
      await _loadTodos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completed todos cleared')),
        );
      }
    }
  }

  void _navigateToAddTodo() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddTodoPage()),
    );

    if (result == true) {
      await _loadTodos();
    }
  }

  void _navigateToEditTodo(Todo todo) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddTodoPage(todoToEdit: todo)),
    );

    if (result == true) {
      await _loadTodos();
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _todos.where((todo) => todo.isCompleted).length;
    final activeCount = _todos.length - completedCount;
    final overdueCount = _todos.where((todo) => todo.isOverdue).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TodoFlow',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Notification sound',
            icon: const Icon(Icons.music_note),
            onSelected: (value) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('selected_sound', value);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      
                      'Sound set to: ${value == 'default' ? 'System default' : value}',
                    ),
                  ),
                );
              }
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'default',
                    child: Text('System default'),
                  ),
                  const PopupMenuItem(
                    value: 'notify',
                    child: Text('Notify (bundled)'),
                  ),
                ],
          ),
          IconButton(
            tooltip: 'Play test sound',
            icon: const Icon(Icons.volume_up),
            onPressed: () async {
              try {
                await NotificationService.playTestSound();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Played test sound / notification'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to play test sound: $e')),
                  );
                }
              }
            },
          ),
          if (_todos.any((todo) => todo.isCompleted))
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear completed',
              onPressed: _clearCompleted,
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter tabs
          Container(
            color: Colors.blue,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All (${_todos.length})',
                      isSelected: _currentFilter == TodoFilter.all,
                      onSelected:
                          () => setState(() => _currentFilter = TodoFilter.all),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Active ($activeCount)',
                      isSelected: _currentFilter == TodoFilter.active,
                      onSelected:
                          () => setState(
                            () => _currentFilter = TodoFilter.active,
                          ),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Done ($completedCount)',
                      isSelected: _currentFilter == TodoFilter.completed,
                      onSelected:
                          () => setState(
                            () => _currentFilter = TodoFilter.completed,
                          ),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Overdue ($overdueCount)',
                      isSelected: _currentFilter == TodoFilter.overdue,
                      onSelected:
                          () => setState(
                            () => _currentFilter = TodoFilter.overdue,
                          ),
                      isOverdue: true,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Todo list
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredTodos.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                      onRefresh: _loadTodos,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 80),
                        itemCount: _filteredTodos.length,
                        itemBuilder: (context, index) {
                          final todo = _filteredTodos[index];
                          return TodoItem(
                            todo: todo,
                            onToggle: () => _toggleTodo(todo),
                            onDelete: () => _deleteTodo(todo.id),
                            onTap: () => _navigateToEditTodo(todo),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddTodo,
        icon: const Icon(Icons.add),
        label: const Text('New Todo'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;

    switch (_currentFilter) {
      case TodoFilter.active:
        message = 'No active todos!\nTake a break! 🎉';
        icon = Icons.check_circle_outline;
        break;
      case TodoFilter.completed:
        message = 'No completed todos yet.\nGet started! 💪';
        icon = Icons.assignment_turned_in_outlined;
        break;
      case TodoFilter.overdue:
        message = 'No overdue todos!\nGreat job staying on track! 🎉';
        icon = Icons.check_circle;
        break;
      case TodoFilter.all:
        message = 'No todos yet!\nTap + to create one';
        icon = Icons.assignment_outlined;
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;
  final bool isOverdue;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
    this.isOverdue = false,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;

    if (isOverdue && isSelected) {
      backgroundColor = Colors.red;
      textColor = Colors.white;
    } else if (isOverdue) {
      backgroundColor = Colors.red.shade700;
      textColor = Colors.white;
    } else if (isSelected) {
      backgroundColor = Colors.white;
      textColor = Colors.blue;
    } else {
      backgroundColor = Colors.blue.shade700;
      textColor = Colors.white;
    }

    return GestureDetector(
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
