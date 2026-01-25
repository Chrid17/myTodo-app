import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import '../../models/todo.dart';
import '../../services/supabase_todo_service.dart';
import '../../services/notification_service.dart';
import '../../services/platform_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

enum TodoFilter { all, active, completed }

class TodoListPage extends StatefulWidget {
  final bool readOnly;
  final List<Todo>? sharedTodos;
  const TodoListPage({super.key, this.readOnly = false, this.sharedTodos});

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> {
  final SupabaseTodoService _todoService = SupabaseTodoService();
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  List<Todo> _todos = [];
  TodoFilter _currentFilter = TodoFilter.all;
  bool _isLoading = true;
  Priority _selectedPriority = Priority.medium;
  DateTime? _selectedDueDate;
  bool get _isReadOnly => widget.readOnly && (widget.sharedTodos != null);
  
  // Multi-select feature
  bool _isSelectionMode = false;
  final Set<String> _selectedTodoIds = {};
  
  // iOS Safari banner
  bool _showIOSBanner = false;

  Stream<List<Todo>>? _todosStream;
  StreamSubscription<List<Todo>>? _todosSub;
  Timer? _uiTick;

  @override
  void initState() {
    super.initState();
    NotificationService.registerInAppNotifier((title, body) {
      if (!mounted) return;
      _showReminderDialog(title, body);
    });
    // Periodic tick to refresh overdue UI state promptly
    _uiTick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {});
    });
    _checkIOSSafari();
    _init();
  }
  
  Future<void> _checkIOSSafari() async {
    if (!kIsWeb) return;
    
    final preferences = await SharedPreferences.getInstance();
    final dismissed = preferences.getBool('ios_banner_dismissed') ?? false;
    if (dismissed) return;
    
    // Show banner for all web users - installing the app improves notifications
    if (mounted) {
      setState(() {
        _showIOSBanner = true;
      });
    }
  }
  
  Future<void> _dismissIOSBanner() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('ios_banner_dismissed', true);
    if (mounted) {
      setState(() {
        _showIOSBanner = false;
      });
    }
  }
  
  void _showInstallGuide() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _InstallGuideSheet(),
    );
  }
  
  void _showReminderDialog(String title, String body) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.alarm, color: Color(0xFFEF4444), size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                body,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This task is now due!',
                        style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Dismiss'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _loadTodos(); // Refresh the list
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
              child: const Text('View Tasks'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _todosSub?.cancel();
    _uiTick?.cancel();
    _taskController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_isReadOnly) {
      setState(() {
        _todos = List<Todo>.from(widget.sharedTodos!);
        _isLoading = false;
      });
    } else {
      // initial load
      await _loadTodos();
      // subscribe realtime
      _todosStream = _todoService.subscribeTodos();
      _todosSub = _todosStream!.listen((items) {
        if (!mounted) return;
        setState(() {
          _todos = items;
        });
      });
      await _maybeShowNotificationPrompt();
    }
  }

  Future<void> _maybeShowNotificationPrompt() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final shown = preferences.getBool('notifications_prompt_shown') ?? false;
      if (shown) return;

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Enable notifications & sound'),
            content: const SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(
                    'To hear reminder sounds for your tasks, allow notifications and tap "Enable & Test".',
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Maybe later'),
                onPressed: () async {
                  await preferences.setBool('notifications_prompt_shown', true);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
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
                  await preferences.setBool('notifications_prompt_shown', true);
                  await preferences.setBool('notifications_primed', true);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      // Error showing notification prompt
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
      case TodoFilter.all:
        return _todos;
    }
  }

  Future<void> _toggleTodo(Todo todo) async {
    if (_isReadOnly) return;
    final updatedTodo = todo.copyWith(isCompleted: !todo.isCompleted);
    await _todoService.updateTodo(updatedTodo);
    await _loadTodos();
  }

  Future<void> _deleteTodo(String id) async {
    if (_isReadOnly) return;
    await _todoService.deleteTodo(id);
    await _loadTodos();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task deleted')),
      );
    }
  }

  // Multi-select methods
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedTodoIds.clear();
      }
    });
  }

  void _toggleTodoSelection(String todoId) {
    setState(() {
      if (_selectedTodoIds.contains(todoId)) {
        _selectedTodoIds.remove(todoId);
      } else {
        _selectedTodoIds.add(todoId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedTodoIds.clear();
      for (final todo in _filteredTodos) {
        _selectedTodoIds.add(todo.id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedTodoIds.isEmpty) return;
    
    final count = _selectedTodoIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tasks'),
        content: Text('Are you sure you want to delete $count task${count > 1 ? 's' : ''}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in _selectedTodoIds.toList()) {
        await _todoService.deleteTodo(id);
      }
      _selectedTodoIds.clear();
      _isSelectionMode = false;
      await _loadTodos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count task${count > 1 ? 's' : ''} deleted')),
        );
      }
    }
  }

  Future<void> _completeSelected() async {
    if (_selectedTodoIds.isEmpty) return;
    
    for (final id in _selectedTodoIds.toList()) {
      final todo = _todos.firstWhere((t) => t.id == id, orElse: () => _todos.first);
      if (!todo.isCompleted) {
        final updatedTodo = todo.copyWith(isCompleted: true);
        await _todoService.updateTodo(updatedTodo);
      }
    }
    _selectedTodoIds.clear();
    _isSelectionMode = false;
    await _loadTodos();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tasks marked as complete')),
      );
    }
  }

  void _editTask(Todo todo) {
    if (_isReadOnly) return;
    // Populate the form with the task data
    _taskController.text = todo.title;
    _descriptionController.text = todo.description;
    setState(() {
      _selectedPriority = todo.priority;
      _selectedDueDate = todo.createdAt;
    });
    
    // Delete the old task - it will be re-added when user clicks +
    _deleteTodo(todo.id);
    
    // Show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Editing task - modify and click + to save')),
    );
  }

  Future<void> _addTask() async {
    if (_isReadOnly) return;
    if (_taskController.text.trim().isEmpty) return;

    final newTodo = Todo(
      id: '', // let Supabase generate UUID
      title: _taskController.text.trim(),
      description: _descriptionController.text.trim(),
      createdAt: _selectedDueDate ?? DateTime.now().add(const Duration(hours: 1)),
      priority: _selectedPriority,
      isCompleted: false,
    );

    await _todoService.addTodo(newTodo);

    // Clear form
    _taskController.clear();
    _descriptionController.clear();
    setState(() {
      _selectedPriority = Priority.medium;
      _selectedDueDate = null;
    });

    await _loadTodos();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task added successfully!')),
      );
    }
  }

  Future<void> _selectDueDate() async {
    if (_isReadOnly) return;
    if (!mounted) return;
    
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF7C3AED),
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDueDate ?? DateTime.now()),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF7C3AED),
              ),
            ),
            child: child!,
          );
        },
      );

      if (time != null && mounted) {
        setState(() {
          _selectedDueDate = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  int get _totalCount => _todos.length;
  int get _activeCount => _todos.where((todo) => !todo.isCompleted).length;
  int get _completedCount => _todos.where((todo) => todo.isCompleted).length;
  int get _highPriorityCount => _todos.where((todo) => todo.priority == Priority.high && !todo.isCompleted).length;

  Future<void> _onSavePressed() async {
    await _loadTodos();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All changes saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
            body: SafeArea(
        child: Column(
          children: [
            if (_isReadOnly)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, color: Color(0xFF1D4ED8)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Viewing a shared list (read-only).',
                        style: TextStyle(color: Color(0xFF1D4ED8)),
                      ),
                    ),
                  ],
                ),
              ),
            // Notification Setup Banner - Simple and user-friendly
            if (_showIOSBanner && kIsWeb)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.notifications_active, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Want Reminders?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Install the app for notifications',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                          onPressed: _dismissIOSBanner,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showInstallGuide,
                            icon: const Icon(Icons.help_outline, size: 20),
                            label: const Text('Show Me How', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF7C3AED),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            // Header with gradient
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE9D5FF), Color(0xFFF5F3FF)],
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  // Title
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      if (!_isReadOnly)
                        IconButton(
                          icon: Icon(
                            _isSelectionMode ? Icons.close : Icons.checklist,
                            color: const Color(0xFF7C3AED),
                          ),
                          tooltip: _isSelectionMode ? 'Cancel Selection' : 'Select Multiple',
                          onPressed: _toggleSelectionMode,
                        ),
                      Expanded(
                        child: Center(
                          child: Text(
                            _isSelectionMode 
                                ? '${_selectedTodoIds.length} Selected'
                                : 'My Tasks',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                        ),
                      ),
                      if (!_isReadOnly && !_isSelectionMode) ...[
                        IconButton(
                          icon: const Icon(Icons.save_outlined, color: Color(0xFF7C3AED)),
                          tooltip: 'Save',
                          onPressed: _onSavePressed,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Color(0xFF7C3AED)),
                          tooltip: 'Refresh',
                          onPressed: _loadTodos,
                        ),
                      ],
                      if (_isSelectionMode) ...[
                        IconButton(
                          icon: const Icon(Icons.select_all, color: Color(0xFF7C3AED)),
                          tooltip: 'Select All',
                          onPressed: _selectAll,
                        ),
                        const SizedBox(width: 8),
                      ],
                      const SizedBox(width: 8),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Organize your day, accomplish your goals',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Stats Cards - Added Padding
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.list_alt,
                            iconColor: const Color(0xFF7C3AED),
                            label: 'Total',
                            count: _totalCount,
                            backgroundColor: const Color(0xFFF3E8FF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.circle_outlined,
                            iconColor: const Color(0xFF3B82F6),
                            label: 'Active',
                            count: _activeCount,
                            backgroundColor: const Color(0xFFDBEAFE),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.check_circle,
                            iconColor: const Color(0xFF10B981),
                            label: 'Completed',
                            count: _completedCount,
                            backgroundColor: const Color(0xFFD1FAE5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.flag,
                            iconColor: const Color(0xFFEF4444),
                            label: 'High Priority',
                            count: _highPriorityCount,
                            backgroundColor: const Color(0xFFFEE2E2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Task Input Area - Added Padding
            if (!_isReadOnly) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Task title input
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _taskController,
                            decoration: const InputDecoration(
                              hintText: 'Add a new task...',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.add, color: Colors.white),
                            onPressed: _addTask,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ],
                    ),
                    
                    // Divider line
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Container(
                        height: 1,
                        color: Colors.grey.shade200,
                      ),
                    ),
                    
                    // Description input
                    TextField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        hintText: 'Add a description (optional)',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      ),
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    
                    // Priority and Due Date
                    Row(
                      children: [
                        // Priority Selector
                        InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: const Text('Select Priority'),
                                contentPadding: const EdgeInsets.symmetric(vertical: 20),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.flag, color: Color(0xFF10B981)),
                                      title: const Text('Low'),
                                      onTap: () {
                                        setState(() => _selectedPriority = Priority.low);
                                        Navigator.pop(context);
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.flag, color: Color(0xFFF59E0B)),
                                      title: const Text('Medium'),
                                      onTap: () {
                                        setState(() => _selectedPriority = Priority.medium);
                                        Navigator.pop(context);
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.flag, color: Color(0xFFEF4444)),
                                      title: const Text('High'),
                                      onTap: () {
                                        setState(() => _selectedPriority = Priority.high);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.flag,
                                  size: 16,
                                  color: _selectedPriority == Priority.high
                                      ? const Color(0xFFEF4444)
                                      : _selectedPriority == Priority.medium
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFF10B981),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _selectedPriority == Priority.high
                                      ? 'High'
                                      : _selectedPriority == Priority.low
                                          ? 'Low'
                                          : 'Medium',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey.shade700),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        
                        // Due Date Selector
                        InkWell(
                          onTap: _selectDueDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade700),
                                const SizedBox(width: 6),
                                Text(
                                  _selectedDueDate == null
                                      ? 'Set due date & time'
                                      : DateFormat('MM/dd HH:mm').format(_selectedDueDate!),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Filter Tabs - Added Padding
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _FilterTab(
                    label: 'All',
                    isSelected: _currentFilter == TodoFilter.all,
                    onTap: () => setState(() => _currentFilter = TodoFilter.all),
                  ),
                  const SizedBox(width: 12),
                  _FilterTab(
                    label: 'Active',
                    isSelected: _currentFilter == TodoFilter.active,
                    onTap: () => setState(() => _currentFilter = TodoFilter.active),
                  ),
                  const SizedBox(width: 12),
                  _FilterTab(
                    label: 'Completed',
                    isSelected: _currentFilter == TodoFilter.completed,
                    onTap: () => setState(() => _currentFilter = TodoFilter.completed),
                  ),
                  const Spacer(),
                  // Priority Filter Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'All Priorities',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey.shade700),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Task List - Added Padding
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED)))
                  : _filteredTodos.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          color: const Color(0xFF7C3AED),
                          onRefresh: _isReadOnly ? () async {} : _loadTodos,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            itemCount: _filteredTodos.length,
                            itemBuilder: (context, index) {
                              final todo = _filteredTodos[index];
                              return _TaskCard(
                                todo: todo,
                                onToggle: _isReadOnly ? () {} : () => _toggleTodo(todo),
                                onDelete: _isReadOnly ? () {} : () => _deleteTodo(todo.id),
                                onEdit: _isReadOnly ? () {} : () => _editTask(todo),
                                isSelectionMode: _isSelectionMode,
                                isSelected: _selectedTodoIds.contains(todo.id),
                                onSelectionToggle: () => _toggleTodoSelection(todo.id),
                              );
                            },
                          ),
                        ),
            ),
            
            // Selection Mode Action Bar
            if (_isSelectionMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selectedTodoIds.isEmpty ? null : _completeSelected,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Complete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _selectedTodoIds.isEmpty ? null : _deleteSelected,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;

    switch (_currentFilter) {
      case TodoFilter.active:
        message = 'No active tasks!\nTake a break! 🎉';
        icon = Icons.check_circle_outline;
        break;
      case TodoFilter.completed:
        message = 'No completed tasks yet.\nGet started! 💪';
        icon = Icons.assignment_turned_in_outlined;
        break;
      case TodoFilter.all:
        message = 'No tasks yet!\nAdd one above to get started';
        icon = Icons.assignment_outlined;
        break;
    }

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }
}

// Stat Card Widget
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  final Color backgroundColor;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Filter Tab Widget
class _FilterTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

// Task Card Widget
class _TaskCard extends StatelessWidget {
  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onSelectionToggle;

  const _TaskCard({
    required this.todo,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = todo.isOverdue;
    
    return GestureDetector(
      onTap: isSelectionMode ? onSelectionToggle : null,
      onLongPress: !isSelectionMode ? onSelectionToggle : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE9D5FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: const Color(0xFF7C3AED), width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: isOverdue 
                  ? const Color(0xFFEF4444).withValues(alpha: 0.1) 
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Priority Indicator Strip (Left Border)
                Container(
                  width: 4,
                  color: isOverdue 
                      ? const Color(0xFFEF4444) 
                      : todo.isCompleted 
                          ? const Color(0xFF10B981) 
                          : _getPriorityColor(todo.priority),
                ),
                
                // Selection Checkbox (only in selection mode)
                if (isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? const Color(0xFF7C3AED) : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF7C3AED) : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Checkbox (hidden in selection mode)
                        if (!isSelectionMode)
                          GestureDetector(
                            onTap: onToggle,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: todo.isCompleted 
                                    ? const Color(0xFF10B981) 
                                    : Colors.transparent,
                                border: Border.all(
                                  color: todo.isCompleted 
                                      ? const Color(0xFF10B981) 
                                      : Colors.grey.shade300,
                                  width: 2,
                                ),
                              ),
                              child: todo.isCompleted
                                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                                  : null,
                            ),
                          ),
                        if (!isSelectionMode) const SizedBox(width: 12),
                      
                      // Text Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              todo.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                decoration: todo.isCompleted 
                                    ? TextDecoration.lineThrough 
                                    : null,
                                color: todo.isCompleted 
                                    ? Colors.grey.shade400 
                                    : Colors.black87,
                              ),
                            ),
                            if (todo.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                todo.description,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                  decoration: todo.isCompleted 
                                      ? TextDecoration.lineThrough 
                                      : null,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            
                            // Tags Row
                            Row(
                              children: [
                                // Priority Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getPriorityColor(todo.priority).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    todo.priority.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: _getPriorityColor(todo.priority),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                
                                // Date/Time
                                Icon(
                                  Icons.access_time, 
                                  size: 14, 
                                  color: isOverdue ? const Color(0xFFEF4444) : Colors.grey.shade400
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('MM/dd HH:mm').format(todo.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                                    color: isOverdue ? const Color(0xFFEF4444) : Colors.grey.shade500,
                                  ),
                                ),
                                
                                // Overdue Badge
                                if (isOverdue) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'OVERDUE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // Actions
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit_outlined, size: 20, color: Colors.grey.shade400),
                            onPressed: onEdit,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey.shade400),
                            onPressed: onDelete,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Color _getPriorityColor(Priority priority) {
    switch (priority) {
      case Priority.high:
        return const Color(0xFFEF4444);
      case Priority.medium:
        return const Color(0xFFF59E0B);
      case Priority.low:
        return const Color(0xFF10B981);
    }
  }
}

// Install Guide Bottom Sheet - User-friendly setup instructions
class _InstallGuideSheet extends StatelessWidget {
  const _InstallGuideSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.install_mobile,
                    size: 48,
                    color: Color(0xFF7C3AED),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Install My Tasks App',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Get reminders even when your browser is closed!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          
          // Instructions
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _buildDeviceSection(
                    'iPhone / iPad',
                    Icons.phone_iphone,
                    const Color(0xFF007AFF),
                    [
                      _StepItem(
                        number: '1',
                        title: 'Tap the Share button',
                        description: 'Look for the square with an arrow at the bottom of Safari',
                        icon: Icons.ios_share,
                      ),
                      _StepItem(
                        number: '2',
                        title: 'Scroll down and tap "Add to Home Screen"',
                        description: 'You may need to scroll down in the menu to find it',
                        icon: Icons.add_box_outlined,
                      ),
                      _StepItem(
                        number: '3',
                        title: 'Tap "Add" in the top right',
                        description: 'The app icon will appear on your home screen',
                        icon: Icons.check_circle_outline,
                      ),
                      _StepItem(
                        number: '4',
                        title: 'Open the app and allow notifications',
                        description: 'Tap "Allow" when asked to receive reminders',
                        icon: Icons.notifications_active,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildDeviceSection(
                    'Android Phone / Tablet',
                    Icons.android,
                    const Color(0xFF34A853),
                    [
                      _StepItem(
                        number: '1',
                        title: 'Tap the menu button',
                        description: 'Look for 3 dots (⋮) in the top right corner of Chrome',
                        icon: Icons.more_vert,
                      ),
                      _StepItem(
                        number: '2',
                        title: 'Tap "Add to Home screen" or "Install app"',
                        description: 'This will install the app on your phone',
                        icon: Icons.add_to_home_screen,
                      ),
                      _StepItem(
                        number: '3',
                        title: 'Open the app and allow notifications',
                        description: 'Tap "Allow" when asked to receive reminders',
                        icon: Icons.notifications_active,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildDeviceSection(
                    'Computer (Windows / Mac)',
                    Icons.laptop,
                    const Color(0xFF4285F4),
                    [
                      _StepItem(
                        number: '1',
                        title: 'Look for the install icon',
                        description: 'In Chrome/Edge, look for a "+" or computer icon in the address bar',
                        icon: Icons.install_desktop,
                      ),
                      _StepItem(
                        number: '2',
                        title: 'Click "Install"',
                        description: 'The app will open in its own window',
                        icon: Icons.download,
                      ),
                      _StepItem(
                        number: '3',
                        title: 'Allow notifications when asked',
                        description: 'Click "Allow" to receive reminders',
                        icon: Icons.notifications_active,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Tip box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb, color: Color(0xFFD97706), size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Why install?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Installing the app allows it to send you reminders even when your browser is closed or your phone is locked.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          
          // Close button
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Got It!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSection(String title, IconData deviceIcon, Color color, List<_StepItem> steps) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Section header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(deviceIcon, color: color, size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          
          // Steps
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: steps.map((step) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          step.number,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  step.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                              ),
                              Icon(step.icon, size: 20, color: Colors.grey.shade500),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            step.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepItem {
  final String number;
  final String title;
  final String description;
  final IconData icon;

  const _StepItem({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
  });
}
