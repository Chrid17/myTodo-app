import 'package:flutter/material.dart';
import '../../models/todo.dart';
import '../../services/todo_service.dart';
import '../../services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

enum TodoFilter { all, active, completed }

class TodoListPage extends StatefulWidget {
  const TodoListPage({super.key});

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> {
  final TodoService _todoService = TodoService();
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  List<Todo> _todos = [];
  TodoFilter _currentFilter = TodoFilter.all;
  bool _isLoading = true;
  Priority _selectedPriority = Priority.medium;
  DateTime? _selectedDueDate;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _taskController.dispose();
    _descriptionController.dispose();
    super.dispose();
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

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
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
    await _todoService.deleteTodo(id);
    await _loadTodos();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task deleted')),
      );
    }
  }

  void _editTask(Todo todo) {
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
    if (_taskController.text.trim().isEmpty) return;

    final newTodo = Todo(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _taskController.text.trim(),
      description: _descriptionController.text.trim(),
      createdAt: _selectedDueDate ?? DateTime.now().add(const Duration(hours: 1)),
      priority: _selectedPriority,
      isCompleted: false,
    );

    await _todoService.addTodo(newTodo);
    
    // Schedule notification if due date is set
    if (_selectedDueDate != null && _selectedDueDate!.isAfter(DateTime.now())) {
      await NotificationService.scheduleNotification(newTodo);
    }

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

    if (date != null) {
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

      if (time != null) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: SafeArea(
        child: Column(
          children: [
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
                  const Text(
                    'My Tasks',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7C3AED),
                    ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
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
                          onRefresh: _loadTodos,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            itemCount: _filteredTodos.length,
                            itemBuilder: (context, index) {
                              final todo = _filteredTodos[index];
                              return _TaskCard(
                                todo: todo,
                                onToggle: () => _toggleTodo(todo),
                                onDelete: () => _deleteTodo(todo.id),
                                onEdit: () => _editTask(todo),
                              );
                            },
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
            color: Colors.black.withOpacity(0.05),
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

  const _TaskCard({
    required this.todo,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = todo.isOverdue;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isOverdue 
                ? const Color(0xFFEF4444).withOpacity(0.1) 
                : Colors.black.withOpacity(0.03),
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
              
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Checkbox
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
                      const SizedBox(width: 12),
                      
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
                                    color: _getPriorityColor(todo.priority).withOpacity(0.1),
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
