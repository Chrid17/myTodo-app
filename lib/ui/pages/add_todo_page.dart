import 'package:flutter/material.dart';
import '../../models/todo.dart';
import '../../services/todo_service.dart';
import '../../services/notification_service.dart';
import '../widgets/emoji_picker_widget.dart';

class AddTodoPage extends StatefulWidget {
  final Todo? todoToEdit;

  const AddTodoPage({super.key, this.todoToEdit});

  @override
  State<AddTodoPage> createState() => _AddTodoPageState();
}

class _AddTodoPageState extends State<AddTodoPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final TodoService _todoService = TodoService();
  bool _isLoading = false;
  Priority _selectedPriority = Priority.medium;
  bool _showEmojiPicker = false;
  String _currentEditingField = 'title'; // 'title' or 'description'
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  bool get _isEditing => widget.todoToEdit != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleController.text = widget.todoToEdit!.title;
      _descriptionController.text = widget.todoToEdit!.description;
      _selectedPriority = widget.todoToEdit!.priority;
      _selectedDate = widget.todoToEdit!.createdAt;
      _selectedTime = TimeOfDay.fromDateTime(widget.todoToEdit!.createdAt);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _showEmojiPickerForField(String field) {
    setState(() {
      _currentEditingField = field;
      _showEmojiPicker = true;
    });
  }

  void _hideEmojiPicker() {
    setState(() {
      _showEmojiPicker = false;
    });
  }

  void _insertEmoji(String emoji) {
    if (_currentEditingField == 'title') {
      final currentText = _titleController.text;
      final selection = _titleController.selection;
      final newText = currentText.replaceRange(
        selection.start,
        selection.end,
        emoji,
      );
      _titleController.text = newText;
      _titleController.selection = TextSelection.fromPosition(
        TextPosition(offset: selection.start + emoji.length),
      );
    } else {
      final currentText = _descriptionController.text;
      final selection = _descriptionController.selection;
      final newText = currentText.replaceRange(
        selection.start,
        selection.end,
        emoji,
      );
      _descriptionController.text = newText;
      _descriptionController.selection = TextSelection.fromPosition(
        TextPosition(offset: selection.start + emoji.length),
      );
    }
    _hideEmojiPicker();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  DateTime _getCombinedDateTime() {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  Future<void> _saveTodo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_isEditing) {
        // Update existing todo
        final updatedTodo = widget.todoToEdit!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          priority: _selectedPriority,
          createdAt: _getCombinedDateTime(),
        );
        await _todoService.updateTodo(updatedTodo);
        // Reschedule notification for updated todo
        try {
          await NotificationService.rescheduleNotification(updatedTodo);
        } catch (e) {
          print('Failed to reschedule notification: $e');
        }
      } else {
        // Create new todo
        final newTodo = Todo(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          createdAt: _getCombinedDateTime(),
          priority: _selectedPriority,
        );
        await _todoService.addTodo(newTodo);
        // Schedule notification for new todo
        try {
          await NotificationService.scheduleNotification(newTodo);
        } catch (e) {
          print('Failed to schedule notification: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Todo updated!' : 'Todo added!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Todo' : 'New Todo',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_isEditing)
            IconButton(
              onPressed: _isLoading ? null : _saveTodo,
              icon: const Icon(Icons.check),
              tooltip: 'Save',
            ),
        ],
      ),
      body: Stack(
        children: [
          Form(
        key: _formKey,
        child: ListView(
              padding: const EdgeInsets.all(20.0),
          children: [
                const SizedBox(height: 8),
            
            // Title field
                _buildSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.title, color: Colors.blue.shade600, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Title',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => _showEmojiPickerForField('title'),
                            icon: const Icon(Icons.emoji_emotions, color: Colors.blue, size: 20),
                            tooltip: 'Add emoji',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'What needs to be done?',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.blue, width: 2),
                ),
                filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
              maxLength: 100,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
            ),
            const SizedBox(height: 20),
            
            // Description field
                _buildSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.description, color: Colors.blue.shade600, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Description',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(Optional)',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => _showEmojiPickerForField('description'),
                            icon: const Icon(Icons.emoji_emotions, color: Colors.blue, size: 20),
                            tooltip: 'Add emoji',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                hintText: 'Add more details...',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.blue, width: 2),
                ),
                filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              textCapitalization: TextCapitalization.sentences,
                        maxLines: 4,
              maxLength: 500,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Priority selection
                _buildSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.flag, color: Colors.blue.shade600, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Priority',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<Priority>(
                            value: _selectedPriority,
                            isExpanded: true,
                            icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                            items: Priority.values.map((Priority priority) {
                              return DropdownMenuItem<Priority>(
                                value: priority,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: _getPriorityColor(priority),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(_getPriorityLabel(priority)),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (Priority? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedPriority = newValue;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Date and Time selection
                _buildSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.blue.shade600, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Due Date & Time',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Date selection
                      _buildDateTimeField(
                        icon: Icons.calendar_today,
                        label: 'Date',
                        value: '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                        onTap: _selectDate,
                      ),
                      const SizedBox(height: 12),
                      // Time selection
                      _buildDateTimeField(
                        icon: Icons.access_time,
                        label: 'Time',
                        value: _selectedTime.format(context),
                        onTap: _selectTime,
                      ),
                    ],
                  ),
            ),
            const SizedBox(height: 32),
            
            // Save button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
              onPressed: _isLoading ? null : _saveTodo,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                ),
                      elevation: 3,
                      shadowColor: Colors.blue.withOpacity(0.3),
              ),
              child: _isLoading
                  ? const SizedBox(
                            height: 24,
                            width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isEditing ? Icons.save : Icons.add,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                      _isEditing ? 'Update Todo' : 'Add Todo',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                              ),
                            ],
                          ),
                  ),
                ),
          ],
        ),
      ),
          // Emoji picker overlay
          if (_showEmojiPicker)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: EmojiPickerWidget(
                onEmojiSelected: _insertEmoji,
                onClose: _hideEmojiPicker,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildDateTimeField({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: Colors.blue,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.end,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_drop_down,
              color: Colors.grey.shade600,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(Priority priority) {
    switch (priority) {
      case Priority.low:
        return Colors.green;
      case Priority.medium:
        return Colors.orange;
      case Priority.high:
        return Colors.red;
    }
  }

  String _getPriorityLabel(Priority priority) {
    switch (priority) {
      case Priority.low:
        return 'Low Priority';
      case Priority.medium:
        return 'Medium Priority';
      case Priority.high:
        return 'High Priority';
    }
  }
}

